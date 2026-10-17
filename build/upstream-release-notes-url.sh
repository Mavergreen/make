#!/bin/sh
# platform: host-agnostic
set -eu
printf 'https://git.savannah.gnu.org/cgit/make.git/tree/NEWS?h=%s\n' "${1:?usage: upstream-release-notes-url.sh <upstream-version>}"
