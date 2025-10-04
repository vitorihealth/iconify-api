#!/bin/bash

set -e

# Semantic Versioning implementation following https://semver.org
# Given a version number MAJOR.MINOR.PATCH, increment the:
# - MAJOR version when you make incompatible API changes
# - MINOR version when you add functionality in a backward compatible manner  
# - PATCH version when you make backward compatible bug fixes

# Validate required environment variables
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
    echo "Usage: $0 <GITHUB_TOKEN> <GIT_REPOSITORY> <GIT_ACTOR> <GIT_EMAIL>"
    exit 1
fi

GITHUB_TOKEN=$1
GIT_REPOSITORY=$2
GIT_ACTOR=$3
GIT_EMAIL=$4

ORIGIN_URL="https://${GIT_ACTOR}:${GITHUB_TOKEN}@github.com/${GIT_REPOSITORY}.git"

git config user.name "$GIT_ACTOR"
git config user.email "$GIT_EMAIL"
git remote set-url origin "$ORIGIN_URL"

# Ensure all tags are fetched
echo "Fetching all tags..."
git fetch --tags --force

# Debug: Show latest tags
echo "::group::Latest tags in repository"
git tag --sort=-version:refname | head -20
echo "::endgroup::"

# Get the latest tag
LATEST_TAG=$(git tag --sort=-version:refname | head -1)
echo "Latest tag: $LATEST_TAG"

# Check if there are commits since the latest tag
if [ -n "$LATEST_TAG" ]; then
    COMMITS_SINCE_TAG=$(git rev-list --count ${LATEST_TAG}..HEAD)
    echo "Commits since $LATEST_TAG: $COMMITS_SINCE_TAG"
    
    if [ "$COMMITS_SINCE_TAG" -eq 0 ]; then
        echo "No commits since latest tag $LATEST_TAG. No release needed."
        echo "version_tag=$LATEST_TAG" >> "$GITHUB_OUTPUT"
        exit 0
    fi
else
    echo "No existing tags found. Starting with version 0.1.0 (initial development phase)"
    LATEST_TAG="0.0.0"
fi

# Parse the latest tag to extract version components (supports v prefix)
# SemVer format: X.Y.Z where X, Y, and Z are non-negative integers
if [[ $LATEST_TAG =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)(-.*)?(\+.*)?$ ]]; then
    MAJOR=${BASH_REMATCH[1]}
    MINOR=${BASH_REMATCH[2]}
    PATCH=${BASH_REMATCH[3]}
    PRERELEASE=${BASH_REMATCH[4]}
    BUILD_METADATA=${BASH_REMATCH[5]}
else
    echo "Invalid or no tag format found. Starting with version 0.1.0 for initial development"
    MAJOR=0
    MINOR=1
    PATCH=0
    PRERELEASE=""
    BUILD_METADATA=""
fi

echo "Current version: $MAJOR.$MINOR.$PATCH${PRERELEASE}${BUILD_METADATA}"

# Analyze commit messages since the latest tag to determine version increment
# Following conventional commits and SemVer specification
if [ -n "$LATEST_TAG" ] && [ "$LATEST_TAG" != "0.0.0" ]; then
    COMMIT_MESSAGES=$(git log --pretty=format:"%s%n%b" ${LATEST_TAG}..HEAD)
else
    COMMIT_MESSAGES=$(git log --pretty=format:"%s%n%b" HEAD)
fi

echo "::group::Analyzing commits for version increment"
echo "$COMMIT_MESSAGES"
echo "::endgroup::"

# Determine version increment based on SemVer rules
INCREMENT_TYPE="patch"  # Default to patch

# Check for breaking changes (MAJOR version increment)
# - Commits with ! after type/scope: feat!: or feat(scope)!:
# - Commits with BREAKING CHANGE: in body or footer
if echo "$COMMIT_MESSAGES" | grep -qE "^[a-zA-Z]+(\([^)]*\))?!:|BREAKING CHANGE:|^[a-zA-Z]+!:"; then
    INCREMENT_TYPE="major"
    echo "Breaking changes detected - MAJOR version increment"
# Check for new features (MINOR version increment)  
# - feat: commits indicate new backward compatible functionality
elif echo "$COMMIT_MESSAGES" | grep -qE "^feat(\([^)]*\))?:"; then
    INCREMENT_TYPE="minor"
    echo "New features detected - MINOR version increment"
# Everything else is PATCH (backward compatible bug fixes)
# - fix: commits, chore:, docs:, style:, refactor:, test:, etc.
else
    INCREMENT_TYPE="patch"
    echo "Bug fixes or other changes detected - PATCH version increment"
fi

# Apply SemVer increment rules
case $INCREMENT_TYPE in
    "major")
        # Major version increment: reset minor and patch to 0
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    "minor")
        # Minor version increment: reset patch to 0, keep major
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    "patch")
        # Patch version increment: keep major and minor
        PATCH=$((PATCH + 1))
        ;;
esac

# For initial development (major version 0), follow SemVer guidelines:
# - 0.y.z is for initial development, anything may change
# - Start at 0.1.0 and increment minor for each release
if [ "$MAJOR" -eq 0 ] && [ "$MINOR" -eq 0 ] && [ "$PATCH" -eq 0 ]; then
    MINOR=1
    PATCH=0
fi

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
echo "Next version ($INCREMENT_TYPE): $NEW_VERSION"
echo "Following Semantic Versioning specification: https://semver.org"

# Check if the tag already exists
if git rev-parse "$NEW_VERSION" >/dev/null 2>&1; then
    TAG_COMMIT_HASH=$(git rev-list -n 1 "$NEW_VERSION")
    CURRENT_COMMIT_HASH=$(git rev-parse HEAD)
    
    echo "Tag $NEW_VERSION exists:"
    echo "  Tag commit: $TAG_COMMIT_HASH"
    echo "  Current commit: $CURRENT_COMMIT_HASH"
    
    if [ "$TAG_COMMIT_HASH" != "$CURRENT_COMMIT_HASH" ]; then
        echo "Error: Tag $NEW_VERSION exists on a different commit"
        echo "Latest tag: $LATEST_TAG, Calculated: $NEW_VERSION"
        echo "This suggests a version calculation issue or the tag was created manually"
        exit 1
    else
        echo "Tag $NEW_VERSION already exists on the current commit. No release needed."
        echo "version_tag=$NEW_VERSION" >> "$GITHUB_OUTPUT"
        exit 0
    fi
else
    # Tag doesn't exist, create new annotated tag
    echo "Creating annotated tag: $NEW_VERSION"
    git tag -a "$NEW_VERSION" -m "Release $NEW_VERSION

Semantic version following https://semver.org
Increment type: $INCREMENT_TYPE"
    echo "Tag $NEW_VERSION created successfully"
fi

# Output the version tag for GitHub Actions
echo "version_tag=$NEW_VERSION" >> "$GITHUB_OUTPUT"