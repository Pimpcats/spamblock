#!/usr/bin/env bash
# Generates SpamBlock.xcodeproj from project.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
	cat >&2 <<-'MSG'
	XcodeGen isn't installed. It turns project.yml into SpamBlock.xcodeproj:

	    brew install xcodegen

	If you'd rather not install it, README.md has the steps to assemble the
	same two targets by hand in Xcode.
	MSG
	exit 1
fi

xcodegen generate

if grep -q 'com\.example' Shared/AppConfiguration.swift; then
	cat <<-'MSG'

	Heads up: the bundle identifiers are still the com.example placeholders.
	They have to be unique to you before the app will run on a device:

	    scripts/configure.sh com.yourname
	MSG
fi

echo
echo "Generated SpamBlock.xcodeproj — open it with: open SpamBlock.xcodeproj"
