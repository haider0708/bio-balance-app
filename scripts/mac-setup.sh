#!/usr/bin/env bash
# Prepares a Mac to build and publish the iPhone app. Safe to run again at any time.
#   git clone https://github.com/haider0708/bio-balance-app.git && bash bio-balance-app/scripts/mac-setup.sh
# It installs and checks the tools, prepares signing and the server connection, and builds the app
# once to prove everything works. It changes nothing in the project that is committed.
set -u
cd "$(dirname "$0")/.."
root=$(pwd)

green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
step()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
problems=0
fail()  { red "✗ $*"; problems=$((problems + 1)); }

[ "$(uname)" = "Darwin" ] || { red "This script is for a Mac."; exit 1; }

step "1/7 Xcode"
if xcodebuild -version >/tmp/xcode-version.txt 2>&1; then
  version=$(head -1 /tmp/xcode-version.txt | sed -E 's/Xcode ([0-9]+).*/\1/')
  if [ "${version:-0}" -ge 26 ]; then green "✓ $(head -1 /tmp/xcode-version.txt)"
  else fail "Xcode $version is too old: Apple requires Xcode 26 or later. Update it from the Mac App Store."; fi
else
  fail "Xcode is not ready. Install Xcode from the Mac App Store, open it once, accept the licence, then run this again."
  echo "   (If it only needs its licence: sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch)"
fi

step "2/7 CocoaPods (with Homebrew or MacPorts)"
# CocoaPods runs on Ruby, which wants a UTF-8 terminal and (MacPorts' Ruby) the system certificates.
profile=~/.zprofile
grep -q '^export LANG=' "$profile" 2>/dev/null || echo 'export LANG="en_US.UTF-8"' >> "$profile"
grep -q '^export SSL_CERT_FILE=' "$profile" 2>/dev/null || echo 'export SSL_CERT_FILE="/etc/ssl/cert.pem"' >> "$profile"
export LANG="en_US.UTF-8" SSL_CERT_FILE="/etc/ssl/cert.pem"
if command -v pod >/dev/null 2>&1; then green "✓ CocoaPods $(pod --version 2>/dev/null)"
elif command -v brew >/dev/null 2>&1; then
  echo "Installing CocoaPods (one plugin of the app needs it)..."
  brew install cocoapods && green "✓ CocoaPods installed" || fail "CocoaPods did not install."
elif command -v port >/dev/null 2>&1; then
  fail "CocoaPods is missing: run 'sudo port install cocoapods', then this script again."
else
  fail "Neither Homebrew nor MacPorts is installed. Install one (https://brew.sh or https://www.macports.org), then run this again."
fi

step "2b Git (so pulling and pushing stay smooth)"
if [ -z "$(git config --global user.name)" ]; then
  printf "Your name for commits: "; read -r gname; [ -n "$gname" ] && git config --global user.name "$gname"
fi
if [ -z "$(git config --global user.email)" ]; then
  printf "Your email for commits: "; read -r gmail; [ -n "$gmail" ] && git config --global user.email "$gmail"
fi
git config --global pull.rebase true
green "✓ git: $(git config --global user.name) <$(git config --global user.email)>, pull = rebase"

step "2c GitHub (so this Mac can push)"
if ! command -v gh >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then brew install gh >/dev/null 2>&1; fi
if ! command -v gh >/dev/null 2>&1; then
  fail "GitHub's tool 'gh' is missing: run 'brew install gh' (or 'sudo port install gh'), then this script again."
else
  if ! gh auth status >/dev/null 2>&1; then
    echo "A browser window opens: sign in to GitHub as haider0708 and confirm the code."
    gh auth login --hostname github.com --git-protocol https --web || true
  fi
  if gh auth status >/dev/null 2>&1; then gh auth setup-git >/dev/null 2>&1; green "✓ GitHub: $(gh api user --jq .login 2>/dev/null) (push works from this Mac)"
  else fail "Not signed in to GitHub: run 'gh auth login', then this script again."; fi
fi

step "3/7 Flutter"
if command -v flutter >/dev/null 2>&1; then
  have=$(flutter --version 2>/dev/null | head -1 | sed -E 's/Flutter ([0-9.]+).*/\1/')
  want=$(sed -E 's/.*"flutter":"([^"]+)".*/\1/' .fvmrc)
  if [ "$have" = "$want" ]; then green "✓ Flutter $have"
  else fail "Flutter is $have but the project uses $want. Install exactly $want (flutter.dev, or: flutter downgrade / flutter upgrade)."; fi
else
  fail "Flutter is not installed (or not on the PATH). Install Flutter $(sed -E 's/.*"flutter":"([^"]+)".*/\1/' .fvmrc) from flutter.dev."
fi

step "4/7 Your Apple Team ID (for signing)"
signing=apps/mobile/ios/Flutter/Signing.xcconfig
if [ -f "$signing" ] && grep -q "^DEVELOPMENT_TEAM *= *[A-Z0-9]\{10\}" "$signing"; then
  green "✓ $signing already has a Team ID"
else
  echo "Find it at developer.apple.com > Account > Membership (10 letters and digits)."
  printf "Team ID (press Enter to skip for now): "
  read -r team
  if [ -z "$team" ]; then echo "Skipped: set it later in $signing (copy Signing.xcconfig.example)."
  elif printf '%s' "$team" | grep -q '^[A-Z0-9]\{10\}$'; then
    printf 'DEVELOPMENT_TEAM = %s\nCODE_SIGN_STYLE = Automatic\n' "$team" > "$signing"
    green "✓ saved in $signing (this file is never committed)"
  else fail "That does not look like a Team ID (10 capital letters/digits)."; fi
fi

step "5/7 Access to the server (SSH)"
key=~/.ssh/go2code_mac
mkdir -p ~/.ssh && chmod 700 ~/.ssh
if [ ! -f "$key" ]; then
  ssh-keygen -t ed25519 -f "$key" -N "" -C "mac" >/dev/null && green "✓ created a key for this Mac"
  echo "   (add a passphrase later with: ssh-keygen -p -f $key)"
else green "✓ the key already exists"; fi
if ! grep -q "^Host go2code$" ~/.ssh/config 2>/dev/null; then
  cat >> ~/.ssh/config <<EOF

Host go2code
    HostName 146.59.195.61
    User ubuntu
    IdentityFile ~/.ssh/go2code_mac
    IdentitiesOnly yes
    ServerAliveInterval 60
EOF
  green "✓ added the server to ~/.ssh/config"
fi
expected="SHA256:8YlE5701MppokFbRrnWKH3i1Sn0L8I6kyAm2yQwdeAE"
seen=$(ssh-keyscan -t ed25519 146.59.195.61 2>/dev/null | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
if [ "$seen" = "$expected" ]; then
  ssh-keygen -F 146.59.195.61 >/dev/null 2>&1 || ssh-keyscan -t ed25519 146.59.195.61 >> ~/.ssh/known_hosts 2>/dev/null
  green "✓ the server's fingerprint matches the expected one"
else
  fail "The server's fingerprint is not the expected one ($seen). Do NOT connect; tell the owner."
fi
cp "$key.pub" ~/Desktop/mac-public-key.txt 2>/dev/null || true
command -v pbcopy >/dev/null 2>&1 && pbcopy < "$key.pub"
echo
echo "   >>> YOUR PUBLIC KEY (safe to share). It is copied to your clipboard and saved on the Desktop"
echo "   >>> as mac-public-key.txt. Paste it to Claude on the Linux PC so it can allow this Mac:"
echo
cat "$key.pub"
echo

step "6/7 The app: dependencies, checks"
cd apps/mobile || exit 1
if command -v flutter >/dev/null 2>&1; then
  flutter pub get --enforce-lockfile >/dev/null 2>&1 && green "✓ dependencies" || fail "flutter pub get failed."
  flutter analyze 2>&1 | tail -1
  if flutter test >/tmp/bb-tests.txt 2>&1; then green "✓ tests: $(tail -1 /tmp/bb-tests.txt)"
  else fail "Some tests failed: see /tmp/bb-tests.txt"; fi
fi

step "7/7 The iPhone build (no signing yet)"
if command -v flutter >/dev/null 2>&1; then
  if flutter build ios --release --no-codesign 2>&1 | tail -3 | tee /tmp/bb-ios.txt | grep -q "Built"; then
    green "✓ the iPhone app builds on this Mac"
  else cat /tmp/bb-ios.txt; fail "The iPhone build failed: send the last lines above to the session."; fi
fi

echo
if [ "$problems" -eq 0 ]; then green "All good. Next: open $root in Claude and say: Read docs/mac-handoff.md and follow it."
else red "$problems thing(s) to fix above, then run this script again."; fi
exit "$problems"
