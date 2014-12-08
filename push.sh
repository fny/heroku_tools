#! /usr/bin/env bash

set -e

#
# Script Arguments
#

push_target="$1" # Heroku repository to push to.
commit_message="$2"

#
# Helpers
#

error_exit() {
  echo "Heroku Push: ${1:-'Unknown Error'}" 1>&2
  exit 1
}

# Cross-platform set in place
sed_in_place() {
  pattern=$1
  file=$2

  if sed --version 2>&1 | grep GNU &>/dev/null; then
    # GNU sed
    sed -i -e "$pattern" "$file"
  else
    # BSD sed
    sed -i '' -e "$pattern" "$file"
  fi
}

show_and_tell() {
  command -v say >/dev/null 2>&1 && say $1
}

#
# Here we go...
#

[ -z "$push_target" ] && error_exit "Please specify a deploy target that matches one of your remotes."

# If the git remote isn't listed, exit.
if ! git remote | grep -e "^${push_target}\$" > /dev/null; then
  error_exit "No matching git remote for deplay target $push_target. Exiting."
fi

# TODO: Check to make sure its a heroku target
# TODO: Are your sure for production?

repo_path=${PWD}
repo_dir_name=${PWD##*/}

# This could be simplied on Linux with `readlink -f`
mkdir -p '../deploys'; cd '../deploys'
deploys_path=${PWD}
cd $repo_path

push_target_url=`git config --get "remote.$push_target.url"`
push_cache_path="${deploys_path}/${repo_dir_name}-${push_target}-cache"

current_branch=`git rev-parse --abbrev-ref HEAD`
timestamp=`date +"%Y%m%d%H%M"`
push_path="${deploys_path}/${repo_dir_name}-${push_target}-${timestamp}"

echo "Syncing cache..."
if [ -d $push_cache_path ]; then
  cd $push_cache_path
  git pull
else
  git clone $push_target_url $push_cache_path
fi

echo "Copying files at $repo_path over for pushing"
cp -R $repo_path $push_path

echo "Entering ${push_path}"
cd $push_path

echo "Trimming Gemfile..."
sed_in_place '/group :development, :test do/,$d' Gemfile

echo "Unignoring seed data..."
sed_in_place 's|/db/seeds/data/||' .gitignore

echo "Unignoring assets..."
sed_in_place 's|/public/assets||' .gitignore

echo "Swapping with cached assets and version control..."
[ -d '.git/' ] && rm -Rf .git/
cp -R "${push_cache_path}/.git" "${push_path}/.git"
[ -d 'public/assets' ] && rm -Rf public/assets
[ -d "${push_cache_path}/public/assets" ] && cp -R "${push_cache_path}/public/assets" "${push_path}/public/assets"

echo "Bundling..."
bundle

echo "Compiling assets..."
RAILS_ENV=production bundle exec rake assets:precompile

echo "Commiting changes..."
git add .
git commit -am "${commit_message:-Push at} ${timestamp}"

echo "Adding $push_target as remote..."
[ ! `git remote | grep "${push_target}"` ] && git remote add $push_target $push_target_url

echo "We have ignition!"
git push $push_target master:master

show_and_tell "I'm so excited! I just can't hide it!"

echo "Cleaning up..."
mv "$push_cache_path" "${push_cache_path}-${timestamp}"
mv "$push_path" "$push_cache_path"

cd $repo_path
