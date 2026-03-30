#!/usr/bin/env python3
"""
Interactive script to set up a new OpenClaw agent with Telegram channel routing.

This script walks through:
1. Creating a new Telegram bot via BotFather instructions
2. Configuring the agent in openclaw.json
3. Adding the Telegram account
4. Creating the binding
5. Restarting the gateway
"""

import json
import os
import sys
from pathlib import Path

CONFIG_PATH = Path.home() / ".openclaw" / "openclaw.json"
AGENTS_DIR = Path.home() / ".openclaw" / "agents"

# Detect if running in multi-agent workspace mode.
# Prefer WORKSPACE_DIR env var (set by setup.sh / migrate.sh / install.sh),
# then try inferring from this script's location inside kit/.
_env_workspace = os.environ.get("WORKSPACE_DIR")
if _env_workspace:
    MULTI_AGENT_WORKSPACE = Path(_env_workspace)
else:
    _script_dir = Path(__file__).resolve().parent
    _inferred = _script_dir.parents[3]  # kit/skills/<skill>/scripts -> workspace
    if (_inferred / "kit" / "workspace-template").is_dir():
        MULTI_AGENT_WORKSPACE = _inferred
    else:
        MULTI_AGENT_WORKSPACE = Path.home() / "workspaces"

WORKSPACE_TEMPLATE = MULTI_AGENT_WORKSPACE / "kit" / "workspace-template"
IS_MULTI_AGENT = MULTI_AGENT_WORKSPACE.exists() and WORKSPACE_TEMPLATE.exists()

if IS_MULTI_AGENT:
    WORKSPACE_BASE = MULTI_AGENT_WORKSPACE
else:
    WORKSPACE_BASE = Path.home() / ".openclaw" / "workspace"


def load_config():
    """Load the OpenClaw configuration."""
    if not CONFIG_PATH.exists():
        print(f"❌ Config not found at {CONFIG_PATH}")
        sys.exit(1)
    
    with open(CONFIG_PATH, "r") as f:
        content = f.read()
    
    # Handle JavaScript-style comments and unquoted keys by using eval-like parsing
    # For safety, we'll use a simple approach: find the JSON structure
    try:
        # Try to parse as-is first (may fail due to JS syntax)
        config = json.loads(content)
    except json.JSONDecodeError:
        # If it fails, we need to handle the JS-style config
        # OpenClaw config uses JavaScript object syntax, not strict JSON
        print("⚠️  Config uses JavaScript syntax. Manual editing required.")
        print(f"   Edit: {CONFIG_PATH}")
        return None
    
    return config


def save_config(config):
    """Save the OpenClaw configuration."""
    # For JS-style config, we need to preserve the format
    # This is a simplified version - in practice, users may need to edit manually
    print("\n⚠️  Automatic config writing requires JavaScript-aware parser.")
    print("   The script will generate the config snippets for you to paste.")
    return False


def get_user_input(prompt, default=None):
    """Get user input with optional default."""
    if default:
        response = input(f"{prompt} [{default}]: ").strip()
        return response if response else default
    return input(f"{prompt}: ").strip()


def yes_no(prompt, default=True):
    """Get yes/no input."""
    default_str = "Y/n" if default else "y/N"
    response = input(f"{prompt} [{default_str}]: ").strip().lower()
    if not response:
        return default
    return response in ("y", "yes")


def step_telegram_bot():
    """Step 1: Telegram bot setup."""
    print("\n" + "="*60)
    print("STEP 1: Create Telegram Bot")
    print("="*60)
    print("""
1. Open Telegram and search for @BotFather
2. Send /newbot command
3. Follow prompts to name your bot (e.g., "MyAgent Bot")
4. Choose a username (must end in 'bot', e.g., "myagent_bot")
5. BotFather will give you a TOKEN like: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz

📝 Save this token - you'll need it below.
""")
    
    bot_token = get_user_input("Enter your bot token")
    
    # Validate token format (basic check)
    if ":" not in bot_token or len(bot_token) < 20:
        print("⚠️  Token looks invalid. Should be like: 123456789:ABCdef...")
        if not yes_no("Continue anyway?"):
            return step_telegram_bot()
    
    return bot_token


def step_agent_config(bot_token):
    """Step 2: Agent configuration."""
    print("\n" + "="*60)
    print("STEP 2: Configure Agent")
    print("="*60)
    
    agent_id = get_user_input("Agent ID (lowercase, hyphens)", default="my-agent")
    agent_name = get_user_input("Agent name (display name)", default=agent_id.replace("-", " ").title())
    
    # Workspace and agent directory
    if IS_MULTI_AGENT:
        # Multi-agent: workspace is a subdirectory of workspaces
        workspace_default = str(WORKSPACE_BASE / agent_id)
    else:
        # Single-agent: workspace in .openclaw
        workspace_default = str(WORKSPACE_BASE / f"workspace.{agent_id.replace('-', '_')}")
    
    workspace = get_user_input("Workspace path", default=workspace_default)
    agent_dir = get_user_input(
        "Agent directory",
        default=str(AGENTS_DIR / agent_id)
    )
    
    # Model selection
    print("\nAvailable models (from your config):")
    print("  - rits-qwen3.5/Qwen/Qwen3.5-397B-A17B-FP8")
    print("  - rits/moonshotai/Kimi-K2.5")
    print("  - local/moonshotai/Kimi-VL-A3B-Instruct")
    print("  - litellm/aws/claude-opus-4-6")
    model = get_user_input(
        "Primary model",
        default="rits-qwen3.5/Qwen/Qwen3.5-397B-A17B-FP8"
    )
    
    return {
        "agent_id": agent_id,
        "agent_name": agent_name,
        "workspace": workspace,
        "agent_dir": agent_dir,
        "model": model,
        "bot_token": bot_token
    }


def detect_existing_sender_ids(config):
    """Look for allowFrom sender IDs already configured in Telegram accounts."""
    sender_ids = set()
    if not config:
        return sorted(sender_ids)
    try:
        accounts = config.get("channels", {}).get("telegram", {}).get("accounts", {})
        for acct in accounts.values():
            for uid in acct.get("allowFrom", []):
                if isinstance(uid, int) and uid > 0:
                    sender_ids.add(uid)
    except (AttributeError, TypeError):
        pass
    return sorted(sender_ids)


def step_channel_config(agent_config, config):
    """Step 3: Telegram channel configuration."""
    print("\n" + "="*60)
    print("STEP 3: Telegram Channel Configuration")
    print("="*60)
    
    account_id = get_user_input(
        "Account ID (for channel config)",
        default=f"{agent_config['agent_id']}_bot"
    )
    
    # AllowFrom - detect existing sender IDs from config
    existing_ids = detect_existing_sender_ids(config)
    
    print("\nWho should be allowed to message this bot?")
    if existing_ids:
        ids_str = ", ".join(str(uid) for uid in existing_ids)
        print(f"  Found existing sender ID(s) in config: {ids_str}")
        allow_from_default = ids_str
    else:
        print("  No existing sender IDs found in config.")
        print("  To find your Telegram user ID, message @userinfobot on Telegram.")
        allow_from_default = None
    
    allow_from_input = get_user_input(
        "Allowed sender IDs (comma-separated)",
        default=allow_from_default
    )
    
    try:
        allow_from = [int(x.strip()) for x in allow_from_input.split(",") if x.strip()]
    except ValueError:
        print("⚠️  Could not parse sender IDs. Please enter numeric IDs separated by commas.")
        allow_from = []
    
    if not allow_from:
        print("⚠️  No valid sender IDs provided. The bot will not accept DMs from anyone.")
        if not yes_no("Continue without sender IDs?", default=False):
            return step_channel_config(agent_config, config)
    
    # DM policy
    print("\nDM Policy options:")
    print("  - allowlist: Only allowFrom users can DM")
    print("  - pairing: Match based on bindings")
    dm_policy = get_user_input("DM policy", default="pairing")
    
    return {
        "account_id": account_id,
        "allow_from": allow_from,
        "dm_policy": dm_policy
    }


def generate_config_snippets(agent_config, channel_config):
    """Generate the config snippets to add."""
    print("\n" + "="*60)
    print("STEP 4: Configuration Snippets")
    print("="*60)
    
    # Agent entry
    agent_snippet = f"""
📋 Add to agents.list:
{json.dumps({
    "id": agent_config["agent_id"],
    "name": agent_config["agent_name"],
    "workspace": agent_config["workspace"],
    "agentDir": agent_config["agent_dir"]
}, indent=2)}
"""
    print(agent_snippet)
    
    # Channel account
    channel_snippet = f"""
📋 Add to channels.telegram.accounts:
{json.dumps({
    channel_config["account_id"]: {
        "enabled": True,
        "dmPolicy": channel_config["dm_policy"],
        "botToken": agent_config["bot_token"],
        "allowFrom": channel_config["allow_from"],
        "groupPolicy": "allowlist",
        "streaming": "partial"
    }
}, indent=2)}
"""
    print(channel_snippet)
    
    # Binding
    binding_snippet = f"""
📋 Add to bindings:
{json.dumps({
    "agentId": agent_config["agent_id"],
    "match": {
        "channel": "telegram",
        "accountId": channel_config["account_id"]
    }
}, indent=2)}
"""
    print(binding_snippet)
    
    return agent_config, channel_config


def step_create_directories(agent_config):
    """Step 5: Create necessary directories."""
    print("\n" + "="*60)
    print("STEP 5: Create Directories")
    print("="*60)
    
    workspace = Path(agent_config["workspace"])
    agent_dir = Path(agent_config["agent_dir"])
    
    if IS_MULTI_AGENT:
        print(f"📁 Multi-agent workspace detected: {MULTI_AGENT_WORKSPACE}")
        print(f"📋 Copying workspace-template to: {workspace}")
        
        if yes_no("Create workspace from template?"):
            import shutil
            if workspace.exists():
                print(f"⚠️  Workspace already exists: {workspace}")
                if not yes_no("Overwrite?"):
                    print("⚠️  Skipping workspace creation")
                    return
                shutil.rmtree(workspace)
            
            shutil.copytree(WORKSPACE_TEMPLATE, workspace)
            print(f"✅ Workspace created from template: {workspace}")
            print(f"\n📝 Next steps for the new agent:")
            print(f"   1. Edit {workspace}/IDENTITY.md")
            print(f"   2. Edit {workspace}/USER.md")
            print(f"   3. Edit {workspace}/TOOLS.md")
        else:
            print("⚠️  Create workspace manually before restarting gateway")
    else:
        print(f"Creating workspace: {workspace}")
        print(f"Creating agent dir: {agent_dir}")
        
        if yes_no("Create these directories?"):
            workspace.mkdir(parents=True, exist_ok=True)
            agent_dir.mkdir(parents=True, exist_ok=True)
            print("✅ Directories created")
        else:
            print("⚠️  Create these manually before restarting gateway")


def main():
    print("="*60)
    print("OpenClaw Telegram Agent Setup")
    print("="*60)
    
    if IS_MULTI_AGENT:
        print(f"""
📁 Multi-agent workspace: {MULTI_AGENT_WORKSPACE}

This script will:
1. Copy workspace-template to create your new agent
2. Configure Telegram bot routing in openclaw.json
3. Set up the workspace with shared skills linked

You'll need:
- A Telegram bot token (from @BotFather)
- To edit your openclaw.json config (script generates snippets)
- To restart the gateway
""")
    else:
        print("""
⚠️  Legacy single-agent mode detected.

Consider migrating to multi-agent workspace:
  mkdir ~/workspaces
  cd ~/workspaces
  git init
  git submodule add https://github.com/jimcadden/openclaw-multiagency.git kit
  ./kit/skills/multiagency-bootstrap/scripts/setup.sh

This script will create a basic single-agent workspace.
""")
    
    if not yes_no("Continue?"):
        sys.exit(0)
    
    config = load_config()
    
    # Step 1: Telegram bot
    bot_token = step_telegram_bot()
    
    # Step 2: Agent config
    agent_config = step_agent_config(bot_token)
    
    # Step 3: Channel config (pass config so we can detect existing sender IDs)
    channel_config = step_channel_config(agent_config, config)
    
    # Step 4: Generate snippets
    generate_config_snippets(agent_config, channel_config)
    
    # Step 5: Create directories
    step_create_directories(agent_config)
    
    # Final step
    print("\n" + "="*60)
    print("FINAL STEP: Restart Gateway")
    print("="*60)
    print("""
After adding the config snippets above to openclaw.json:

  openclaw gateway restart

Or use the gateway tool in your session.

✅ Setup complete! Your new agent should now receive messages
   from the Telegram bot you created.
""")


if __name__ == "__main__":
    main()
