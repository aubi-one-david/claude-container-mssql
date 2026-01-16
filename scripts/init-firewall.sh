#!/bin/bash
# Initialize iptables firewall for Claude Container
# Restricts outbound traffic to whitelisted destinations only

set -e

# Determine if we need sudo for iptables
# (When using --userns=keep-id, we have direct capability access)
IPTABLES_CMD="iptables"
if ! iptables -L OUTPUT -n >/dev/null 2>&1; then
    if $IPTABLES_CMD -L OUTPUT -n >/dev/null 2>&1; then
        IPTABLES_CMD="$IPTABLES_CMD"
    else
        echo "Warning: Cannot configure firewall (missing NET_ADMIN capability)"
        echo "Run container with: --cap-add NET_ADMIN"
        exit 1
    fi
fi

# Flush existing rules
$IPTABLES_CMD -F OUTPUT

# Default policy: DROP all outbound
$IPTABLES_CMD -P OUTPUT DROP

# Allow loopback
$IPTABLES_CMD -A OUTPUT -o lo -j ACCEPT

# Allow established/related connections
$IPTABLES_CMD -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS (required for hostname resolution)
$IPTABLES_CMD -A OUTPUT -p udp --dport 53 -j ACCEPT
$IPTABLES_CMD -A OUTPUT -p tcp --dport 53 -j ACCEPT

# ============================================
# ALWAYS ALLOWED DESTINATIONS
# ============================================

# Claude/Anthropic endpoints (required for Claude Code)
$IPTABLES_CMD -A OUTPUT -d api.anthropic.com -p tcp --dport 443 -j ACCEPT
$IPTABLES_CMD -A OUTPUT -d anthropic.com -p tcp --dport 443 -j ACCEPT
$IPTABLES_CMD -A OUTPUT -d console.anthropic.com -p tcp --dport 443 -j ACCEPT
$IPTABLES_CMD -A OUTPUT -d statsig.anthropic.com -p tcp --dport 443 -j ACCEPT
$IPTABLES_CMD -A OUTPUT -d sentry.io -p tcp --dport 443 -j ACCEPT

# npm registry (for MCP servers and updates)
$IPTABLES_CMD -A OUTPUT -d registry.npmjs.org -p tcp --dport 443 -j ACCEPT

# GitHub (for git operations)
$IPTABLES_CMD -A OUTPUT -d github.com -p tcp --dport 443 -j ACCEPT
$IPTABLES_CMD -A OUTPUT -d github.com -p tcp --dport 22 -j ACCEPT
$IPTABLES_CMD -A OUTPUT -d objects.githubusercontent.com -p tcp --dport 443 -j ACCEPT
$IPTABLES_CMD -A OUTPUT -d raw.githubusercontent.com -p tcp --dport 443 -j ACCEPT

# PyPI (for Python packages)
$IPTABLES_CMD -A OUTPUT -d pypi.org -p tcp --dport 443 -j ACCEPT
$IPTABLES_CMD -A OUTPUT -d files.pythonhosted.org -p tcp --dport 443 -j ACCEPT

# ============================================
# DATABASE SERVER (from environment)
# ============================================
if [ -n "$DB_SERVER" ]; then
    DB_PORT="${DB_PORT:-1433}"
    DB_RULE_ADDED=false

    # Try to add rule by IP or hostname
    if [[ "$DB_SERVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # It's an IP address - use directly
        $IPTABLES_CMD -A OUTPUT -d "$DB_SERVER" -p tcp --dport "$DB_PORT" -j ACCEPT
        echo "Allowed database: $DB_SERVER:$DB_PORT"
        DB_RULE_ADDED=true
    else
        # It's a hostname - try to let iptables resolve it
        if $IPTABLES_CMD -A OUTPUT -d "$DB_SERVER" -p tcp --dport "$DB_PORT" -j ACCEPT 2>/dev/null; then
            echo "Allowed database: $DB_SERVER:$DB_PORT"
            DB_RULE_ADDED=true
        else
            # Try manual resolution with getent
            DB_IP=$(getent hosts "$DB_SERVER" 2>/dev/null | awk '{ print $1 }' | head -1)
            if [ -n "$DB_IP" ]; then
                $IPTABLES_CMD -A OUTPUT -d "$DB_IP" -p tcp --dport "$DB_PORT" -j ACCEPT
                echo "Allowed database: $DB_SERVER ($DB_IP):$DB_PORT"
                DB_RULE_ADDED=true
            fi
        fi
    fi

    # Fallback: allow port to any destination if resolution failed
    if [ "$DB_RULE_ADDED" = "false" ]; then
        echo "Warning: Could not resolve DB_SERVER: $DB_SERVER"
        echo "         Allowing port $DB_PORT to any destination"
        $IPTABLES_CMD -A OUTPUT -p tcp --dport "$DB_PORT" -j ACCEPT
    fi
fi

# ============================================
# WEB ACCESS (controlled by toggle)
# ============================================
if [ "$CLAUDE_WEB_ACCESS" = "on" ]; then
    # Allow all HTTP/HTTPS when web access is enabled
    $IPTABLES_CMD -A OUTPUT -p tcp --dport 80 -j ACCEPT
    $IPTABLES_CMD -A OUTPUT -p tcp --dport 443 -j ACCEPT
    echo "Web access: ENABLED (all HTTP/HTTPS allowed)"
else
    echo "Web access: DISABLED (use 'claude-web on' to enable)"
fi

# Log dropped packets (for debugging)
# $IPTABLES_CMD -A OUTPUT -j LOG --log-prefix "DROPPED: " --log-level 4

echo "Firewall initialized successfully"
# Uncomment for debugging:
# $IPTABLES_CMD -L OUTPUT -n --line-numbers
