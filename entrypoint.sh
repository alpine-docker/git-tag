#!/bin/bash

set -o pipefail

# config
default_semvar_bump=${DEFAULT_BUMP:-patch}
with_v=${WITH_V:-false}
release_branches=${RELEASE_BRANCHES:-master,main}
custom_tag=${CUSTOM_TAG}
source=${SOURCE:-.}
dryrun=${DRY_RUN:-false}
initial_version=${INITIAL_VERSION:-0.0.0}
tag_context=${TAG_CONTEXT:-repo}
suffix=${PRERELEASE_SUFFIX:-rc}
verbose=${VERBOSE:-true}

# since https://github.blog/2022-04-12-git-security-vulnerability-announced/ runner uses?
workspace=$(pwd)
git config --global --add safe.directory ${workspace}

cd ${workspace}/${source}

echo "*** CONFIGURATION ***"
echo -e "\tDEFAULT_BUMP: ${default_semvar_bump}"
echo -e "\tWITH_V: ${with_v}"
echo -e "\tRELEASE_BRANCHES: ${release_branches}"
echo -e "\tCUSTOM_TAG: ${custom_tag}"
echo -e "\tSOURCE: ${source}"
echo -e "\tDRY_RUN: ${dryrun}"
echo -e "\tINITIAL_VERSION: ${initial_version}"
echo -e "\tTAG_CONTEXT: ${tag_context}"
echo -e "\tPRERELEASE_SUFFIX: ${suffix}"
echo -e "\tVERBOSE: ${verbose}"

#current_branch=$(git rev-parse --abbrev-ref HEAD)
#current_branch=$(git branch --show-current)

# pre_release="true"
# IFS=',' read -ra branch <<< "$release_branches"
# for b in "${branch[@]}"; do
#     echo "Is $b a match for ${current_branch}"
#     if [[ "${current_branch}" =~ $b ]]
#     then
#         pre_release="false"
#     fi
# done
#echo "pre_release = $pre_release"
pre_release="false"

# fetch tags
git fetch --tags -f
    
tagFmt="^v?[0-9]+\.[0-9]+\.[0-9]+$" 
preTagFmt="^v?[0-9]+\.[0-9]+\.[0-9]+(-$suffix\.[0-9]+)?$" 

# get latest tag that looks like a semver (with or without v)
case "$tag_context" in
    *repo*) 
        taglist="$(git for-each-ref --sort=-v:refname --format '%(refname:lstrip=2)' | grep -E "$tagFmt")"
        tag="$(semver $taglist | tail -n 1)"

        pre_taglist="$(git for-each-ref --sort=-v:refname --format '%(refname:lstrip=2)' | grep -E "$preTagFmt")"
        pre_tag="$(semver "$pre_taglist" | tail -n 1)"
        ;;
    *branch*) 
        taglist="$(git tag --list --merged HEAD --sort=-v:refname | grep -E "$tagFmt")"
        tag="$(semver $taglist | tail -n 1)"

        pre_taglist="$(git tag --list --merged HEAD --sort=-v:refname | grep -E "$preTagFmt")"
        pre_tag=$(semver "$pre_taglist" | tail -n 1)
        ;;
    * ) echo "Unrecognised context"; exit 1;;
esac


# if there are none, start tags at INITIAL_VERSION which defaults to 0.0.0
if [ -z "$tag" ]
then
    log=$(git log --pretty='%B')
    tag="$initial_version"
    if [ -z "$pre_tag" ] && $pre_release
    then
      pre_tag="$initial_version"
    fi
else
    log=$(git log $tag..HEAD --pretty='%B')
fi

# get current commit hash for tag
tag_commit=$(git rev-list -n 1 $tag)

# get current commit hash
commit=$(git rev-parse HEAD)

if [ "$tag_commit" == "$commit" ]; then
    echo "No new commits since previous tag. Skipping..."
    echo ::set-output name=tag::$tag
    echo "tagName=${tag}" >> build.env
    echo "existTag=true" >> build.env
    exit 0
fi

# echo log if verbose is wanted
if $verbose
then
  echo $log
fi

case "$log" in
    *#major* ) new=$(semver -i major $tag); part="major";;
    *#minor* ) new=$(semver -i minor $tag); part="minor";;
    *#patch* ) new=$(semver -i patch $tag); part="patch";;
    *#none* ) 
        echo "Default bump was set to none. Skipping..."; echo ::set-output name=new_tag::$tag; echo ::set-output name=tag::$tag; exit 0;;
    * ) 
        if [ "$default_semvar_bump" == "none" ]; then
            echo "Default bump was set to none. Skipping..."; echo ::set-output name=new_tag::$tag; echo ::set-output name=tag::$tag; exit 0 
        else 
            new=$(semver -i "${default_semvar_bump}" $tag); part=$default_semvar_bump 
        fi 
        ;;
esac

if $pre_release
then
    # Already a prerelease available, bump it
    if [[ "$pre_tag" == *"$new"* ]]; then
        new=$(semver -i prerelease $pre_tag --preid $suffix); part="pre-$part"
    else
        new="$new-$suffix.1"; part="pre-$part"
    fi
fi

echo $part

# prefix with 'v'
if $with_v
then
	new="v$new"
fi

if [ ! -z $custom_tag ]
then
    new="$custom_tag"
fi

if $pre_release
then
    echo -e "Bumping tag ${pre_tag}. \n\tNew tag ${new}"
else
    echo -e "Bumping tag ${tag}. \n\tNew tag ${new}"
fi

# set outputs
echo ::set-output name=new_tag::$new
echo ::set-output name=part::$part

# use dry run to determine the next tag
if $dryrun
then
    echo ::set-output name=tag::$tag
    exit 0
fi 

echo ::set-output name=tag::$new

# gitlab: Pass an environment variable to another job
# https://docs.gitlab.com/ee/ci/variables/index.html#pass-an-environment-variable-to-another-job
echo "tagName=${new}" >> build.env
echo "existTag=false" >> build.env
