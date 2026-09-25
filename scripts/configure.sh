#!/usr/bin/env bash
# Rewrites the bundle identifier prefix across every file that has to agree on
# it: AppConfiguration.swift, project.yml, and both .entitlements files.
#
#     scripts/configure.sh com.yourname [TEAMID]
#
# Safe to re-run: it reads the current prefix out of AppConfiguration.swift
# rather than assuming the placeholder is still there.
set -euo pipefail
cd "$(dirname "$0")/.."

new_prefix="${1:-}"
team_id="${2:-}"

if [[ -z "$new_prefix" ]]; then
	echo "usage: scripts/configure.sh <bundle-id-prefix> [development-team-id]" >&2
	echo "example: scripts/configure.sh com.janedoe ABCDE12345" >&2
	exit 64
fi

if ! [[ "$new_prefix" =~ ^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+$ ]]; then
	echo "error: '$new_prefix' isn't a reverse-DNS prefix, e.g. com.janedoe" >&2
	exit 64
fi

old_prefix=$(sed -n 's/^.*appGroupIdentifier = "group\.\(.*\)\.spamblock".*$/\1/p' Shared/AppConfiguration.swift)
if [[ -z "$old_prefix" ]]; then
	echo "error: couldn't read the current prefix from Shared/AppConfiguration.swift" >&2
	exit 1
fi

if [[ "$old_prefix" == "$new_prefix" ]]; then
	echo "Already set to $new_prefix."
else
	# Escape dots so the old prefix is matched literally.
	escaped_old=${old_prefix//./\\.}

	files=(
		Shared/AppConfiguration.swift
		project.yml
		SpamBlock/SpamBlock.entitlements
		CallDirectoryExtension/CallDirectoryExtension.entitlements
	)

	# -i.bak works on both BSD sed (macOS) and GNU sed.
	sed -i.bak \
		-e "s/${escaped_old}\.spamblock/${new_prefix}.spamblock/g" \
		-e "s/bundleIdPrefix: ${escaped_old}/bundleIdPrefix: ${new_prefix}/" \
		"${files[@]}"
	rm -f "${files[@]/%/.bak}"

	echo "Bundle identifiers now start with $new_prefix:"
	echo "  app        $new_prefix.spamblock"
	echo "  extension  $new_prefix.spamblock.CallDirectory"
	echo "  known spam $new_prefix.spamblock.KnownSpam"
	echo "  app group  group.$new_prefix.spamblock"
fi

if [[ -n "$team_id" ]]; then
	sed -i.bak "s/DEVELOPMENT_TEAM: \"[^\"]*\"/DEVELOPMENT_TEAM: \"${team_id}\"/" project.yml
	rm -f project.yml.bak
	echo "  team       $team_id"
fi

echo
echo "Now run scripts/bootstrap.sh to regenerate the Xcode project."
