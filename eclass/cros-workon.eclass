# Copyright (c) 2012 The Chromium OS Authors. All rights reserved.
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: cros-workon.eclass
# @MAINTAINER:
# ChromiumOS Build Team
# @BUGREPORTS:
# Please report bugs via http://crbug.com/new (with label Build)
# @VCSURL: https://chromium.googlesource.com/chromiumos/overlays/chromiumos-overlay/+/master/eclass/@ECLASS@
# @BLURB: helper eclass for building ChromiumOS packages from git
# @DESCRIPTION:
# A lot of ChromiumOS packages (src/platform/ and src/third_party/) are
# managed in the same way.  You've got a git tree and you want to build
# it.  This automates a lot of that common stuff in one place.

inherit cros-constants

# Array variables. All of the following variables can contain multiple items
# with the restriction being that all of them have to have either:
# - the same number of items globally
# - one item as default for all
# - no items as the cros-workon default
# The exceptions are:
# - CROS_WORKON_PROJECT has to have all items specified.
# - CROS_WORKON_TREE is not listed here because it may not have the same number
#   of items as other array variables when CROS_WORKON_SUBTREE is used.
#   See the variable description below for more details.
ARRAY_VARIABLES=(
	CROS_WORKON_{SUBTREE,REPO,PROJECT,LOCALNAME,DESTDIR,COMMIT,SRCPATH} )

# @ECLASS-VARIABLE: CROS_WORKON_SUBTREE
# @DESCRIPTION:
# Subpaths of the source checkout to be used in the build, separated by
# whitespace. Normally this will be set to directories, but files are also
# allowed if necessary.
# Default value is an empty string, meaning the whole source checkout is used.
# It is strongly recommended to set this variable if the source checkout
# contains multiple packages (e.g. platform2) to avoid unnecessary uprev when
# unrelated files in the repository are modified.
# Access to files outside of these subpaths will be denied.
: ${CROS_WORKON_SUBTREE:=}

# @ECLASS-VARIABLE: CROS_WORKON_REPO
# @DESCRIPTION:
# The base git URL to locate the remote repository.  This is usually the root of
# the GoB server.  It could be any git server, but for infra reliability, our
# policy is to only refer to servers we maintain (e.g. googlesource.com).
# It is combined with CROS_WORKON_PROJECT to form the full URL.
# Look at the cros-constants eclass for common values.
: ${CROS_WORKON_REPO:=${CROS_GIT_HOST_URL}}

# @ECLASS-VARIABLE: CROS_WORKON_PROJECT
# @DESCRIPTION:
# The path on the remote server (beneath CROS_WORKON_REPO) to find the git repo.
# This has no relationship to where the source is checked out locally in the
# manifest.  If looking at a manifest.xml, this is the "name" attribute of the
# "project" tag.
: ${CROS_WORKON_PROJECT:=}

# @ECLASS-VARIABLE: CROS_WORKON_LOCALNAME
# @DESCRIPTION:
# The relative path in the local manifest checkout to find the local git
# checkout.  The exact path it is relative to depends on the CATEGORY of the
# ebuild.  For chromeos-base packages, this is relative to src/.  For all other
# packages, it is relative to src/third_party/.  This applies to all ebuilds
# regardless of the overlay they live in.
# If looking at a manifest.xml, this is related to the "path" attribute of the
# "project" tag (although that path is relative to the root of the manifest).
: ${CROS_WORKON_LOCALNAME:=${PN}}

# @ECLASS-VARIABLE: CROS_WORKON_DESTDIR
# @DESCRIPTION:
# Destination directory in ${WORKDIR} for checkout. It must be under ${S}.
# Note that the default is ${S}, but is only referenced in src_unpack for
# ebuilds that would like to override it.
: ${CROS_WORKON_DESTDIR:=}

# @ECLASS-VARIABLE: CROS_WORKON_COMMIT
# @DESCRIPTION:
# Git commit hashes of the source repositories.
# It is guaranteed that files identified by tree hashes in CROS_WORKON_TREE
# can be found in the commit.
# CROW_WORKON_COMMIT is updated only when CROS_WORKON_TREE below is updated,
# so it does not necessarily point to HEAD in the source repository.
: ${CROS_WORKON_COMMIT:=master}

# @ECLASS-VARIABLE: CROS_WORKON_TREE
# @DESCRIPTION:
# Git tree hashes of the contents of the source repositories.
# If CROS_WORKON_SUBTREE is set, tree hashes are taken from specified subpaths;
# otherwise, they are taken from the root directories of the source
# repositories. Therefore note that CROS_WORKON_TREE may have different number
# of entries than CROS_WORKON_COMMIT if multiple subpaths are specified in
# CROS_WORKON_SUBTREE.
# This is used for verifying the correctness of prebuilts. Unlike the commit
# hash, this hash is unaffected by the history of the repository, or by
# commit messages.
: ${CROS_WORKON_TREE:=}

# Scalar variables. These variables modify the behaviour of the eclass.

# @ECLASS-VARIABLE: CROS_WORKON_SUBDIRS_TO_COPY
# @DESCRIPTION:
# Make cros-workon operate exclusively with the subtrees given by this array.
# NOTE: This only speeds up local_cp builds. Inplace/local_git builds are unaffected.
# It will also be disabled by using project arrays, rather than a single project.
: ${CROS_WORKON_SUBDIRS_TO_COPY:=/}

# @ECLASS-VARIABLE: CROS_WORKON_SUBDIRS_TO_REV
# @DESCRIPTION:
# Array of directories in the source tree. If defined, this causes this ebuild
# to only uprev if there are changes within the specified subdirectories.
: ${CROS_WORKON_SUBDIRS_TO_REV:=/}

# @ECLASS-VARIABLE: CROS_WORKON_SRCROOT
# @DESCRIPTION:
# Root of the manifest checkout.  The src/platform/ and src/third_party/ and
# related trees all live here.  It is extremely uncommon for any package to
# want to access this path, so please think twice (or consult with someone)
# before doing so.  All source code that an ebuild needs should be listed in
# its CROS_WORKON_PROJECT settings (so changes can be properly tracked).
: ${CROS_WORKON_SRCROOT:="${CHROOT_SOURCE_ROOT}"}

# @ECLASS-VARIABLE: CROS_WORKON_INPLACE
# @DESCRIPTION:
# Build the sources in place.  Don't copy them to a temp dir.  No ebuild should
# set this itself as it is meant for other tools (e.g. cros_workon_make).
: ${CROS_WORKON_INPLACE:=}

# @ECLASS-VARIABLE: CROS_WORKON_USE_VCSID
# @DESCRIPTION:
# Export VCSID into the project.  This may contain information like the git
# commit of the project's checkout as well as the current package version.
# Most packages do not use this, so unless you're sure you do, do not set it.
: ${CROS_WORKON_USE_VCSID:=}

# @ECLASS-VARIABLE: CROS_WORKON_GIT_SUFFIX
# @DESCRIPTION:
# The git eclass does not do locking on its repo.  That means
# multiple ebuilds that use the same git repo cannot safely be
# emerged at the same time.  Until we can get that sorted out,
# allow ebuilds that know they'll conflict to declare a unique
# path for storing the local clone.
: ${CROS_WORKON_GIT_SUFFIX:=}

# @ECLASS-VARIABLE: CROS_WORKON_OUTOFTREE_BUILD
# @DESCRIPTION:
# Do not copy the source tree to $S; instead set $S to the
# source tree and store compiled objects and build state
# in $WORKDIR.  The ebuild is responsible for ensuring
# the build output goes to $WORKDIR, e.g. setting
# O=${WORKDIR}/${P}/build/${board} when compiling the kernel.
: ${CROS_WORKON_OUTOFTREE_BUILD:=}

# @ECLASS-VARIABLE: CROS_WORKON_INCREMENTAL_BUILD
# @DESCRIPTION:
# If set to "1", store output objects in a location that is not wiped
# between emerges.  If disabled, objects will be written to ${WORKDIR}
# like normal.
: ${CROS_WORKON_INCREMENTAL_BUILD:=}

# @ECLASS-VARIABLE: CROS_WORKON_BLACKLIST
# @DESCRIPTION:
# If set to "1", the cros-workon uprev system on the bots will not automatically
# revbump your package when changes are made.  This is useful if you want more
# direct control over when updates to the source git repo make it into the
# ebuild, or if the git repo you're using is not part of the official manifest.
# e.g. If you set CROS_WORKON_REPO or EGIT_REPO_URI to an external (to Google)
# site, set this to "1".
: ${CROS_WORKON_BLACKLIST:=}

# @ECLASS-VARIABLE: CROS_WORKON_MAKE_COMPILE_ARGS
# @DESCRIPTION:
# Args to pass to `make` when running src_compile. Not intended for ebuilds
# to set, just to respect. Used by `cros_workon_make` and friends.

# @ECLASS-VARIABLE: CROS_WORKON_EGIT_BRANCH
# @DESCRIPTION:
# This branch is used as EGIT_BRANCH when falling back to git-2. Leaving this
# as the default value of space will cause git-2 to fetch all branches with
# the special refspec ":". Since we don't know which branch CROS_WORKON_COMMIT
# is in, fetching all branches is a safe bet. However, if the git branch being
# updated can't be fast-forwarded (e.g. linux-next master), the branch needs to
# be specified because the special refspec excludes non-FF branches in fetches.
: ${CROS_WORKON_EGIT_BRANCH:=}

# @ECLASS-VARIABLE: CROS_WORKON_ALWAYS_LIVE
# @DESCRIPTION:
# If set to "1", don't try to do a local fetch for 9999 ebuilds.
: ${CROS_WORKON_ALWAYS_LIVE:=}

# @ECLASS-VARIABLE: CROS_WORKON_SRCPATH
# @DESCRIPTION:
# Location of the source directory relative to the brick source root. This is
# used for locally sourced packages and, if defined, takes precedence over
# Chrome OS specific source locations.
: ${CROS_WORKON_SRCPATH:=}

# Join the tree commits to produce a unique identifier
CROS_WORKON_TREE_COMPOSITE=$(IFS="_"; echo "${CROS_WORKON_TREE[*]}")
IUSE="cros_host cros_workon_tree_$CROS_WORKON_TREE_COMPOSITE"

inherit flag-o-matic toolchain-funcs

# We need git-2 only for packages that define CROS_WORKON_PROJECT. Otherwise,
# there's no dependence on git and we don't want it pulled in.
if [[ -n "${CROS_WORKON_PROJECT[*]}" ]]; then
	inherit git-2
fi

# Block deprecated vars.
if [[ ${CROS_WORKON_SUBDIR+set} == "set" ]]; then
	die "CROS_WORKON_SUBDIR is no longer supported.  Please use CROS_WORKON_LOCALNAME instead."
fi

# Sanitize all variables, autocomplete where necessary.
# This function possibly modifies all CROS_WORKON_ variables inplace. It also
# provides a global project_count variable which contains the number of
# projects.
array_vars_autocomplete() {
	# CROS_WORKON_{PROJECT,SRCPATH} must have all values explicitly filled in.
	# They have to be of the same length, or one may be undefined (length <= 1
	# and empty).
	project_count=${#CROS_WORKON_PROJECT[@]}
	local srcpath_count=${#CROS_WORKON_SRCPATH[@]}
	if [[ ${project_count} -lt ${srcpath_count} ]]; then
		if [[ ${project_count} -gt 1 ]] || [[ -n "${CROS_WORKON_PROJECT[@]}" ]]; then
			die "CROS_WORKON_PROJECT has fewer values than _SRCPATH"
		fi
		project_count=${srcpath_count}
	elif [[ ${project_count} -gt ${srcpath_count} ]]; then
		if [[ ${srcpath_count} -gt 1 ]] || [[ -n "${CROS_WORKON_SRCPATH[@]}" ]]; then
			die "CROS_WORKON_SRCPATH has fewer values than _PROJECT"
		fi
	fi

	# No project_count is really bad.
	if [[ ${project_count} -eq 0 ]]; then
		die "Must have at least one value in CROS_WORKON_{PROJECT,SRCPATH}"
	fi
	# For one value, defaults will suffice, unless it's blank (likely undefined).
	if [[ ${project_count} -eq 1 ]]; then
		if [[ -z "${CROS_WORKON_SRCPATH[@]}" ]] && [[ -z "${CROS_WORKON_PROJECT[@]}" ]]; then
			die "Undefined CROS_WORKON_{PROJECT,SRCPATH}"
		fi
		return
	fi

	[[ ${CROS_WORKON_OUTOFTREE_BUILD} == "1" ]] && die "Out of Tree Build not compatible with multi-project ebuilds"

	local count var
	for var in "${ARRAY_VARIABLES[@]}"; do
		eval count=\${#${var}\[@\]}
		if [[ ${count} -ne ${project_count} ]] && [[ ${count} -ne 1 ]]; then
			die "${var} has ${count} projects. ${project_count} or one default expected."
		fi
		# Invariably, ${project_count} is at least 2 here. All variables also either
		# have all items or the first serves as default (or isn't needed if
		# empty). By looking at the second item, determine if we need to
		# autocomplete.
		local i
		if [[ ${count} -ne ${project_count} ]]; then
			for (( i = 1; i < project_count; ++i )); do
				eval ${var}\[i\]=\${${var}\[0\]}
			done
		fi
		eval einfo "${var}: \${${var}[@]}"
	done
}

# Calculate path where code should be checked out.
# Result passed through global variable "path" to preserve proper array quoting.
get_paths() {
	local pathbase srcbase
	pathbase="${CROS_WORKON_SRCROOT}"

	if [[ "${CATEGORY}" == "chromeos-base" ||
		"${CATEGORY}" == "brillo-base" ]] ; then
		pathbase+=/src
	else
		pathbase+=/src/third_party
	fi

	srcbase="$(dirname "$(dirname "$(dirname "$(dirname "${EBUILD}")")")")/src"

	path=()
	local pathelement i
	for (( i = 0; i < project_count; ++i )); do
		if [[ -n "${CROS_WORKON_SRCPATH[i]}" ]]; then
			pathelement="${CROS_WORKON_SRCROOT}/${CROS_WORKON_SRCPATH[i]}"
		else
			pathelement="${pathbase}/${CROS_WORKON_LOCALNAME[i]}"
			if [[ ! -d "${pathelement}" ]]; then
				pathelement="${pathbase}/platform/${CROS_WORKON_LOCALNAME[i]}"
			fi
		fi
		path+=( "${pathelement}" )
	done
}

local_copy_cp() {
	local src="${1}"
	local dst="${2}"
	einfo "Copying sources from ${src}"
	local blacklist=(
		# Python compiled objects are a pain.
		"--exclude=*.py[co]"
		# Assume any dir named ".git" is an actual git dir.  We don't copy them
		# as the ones created by `repo` are full of symlinks which are skipped
		# due to --safe-links below which makes the git dir useless.
		"--exclude=.git/"
	)

	local sl
	for sl in "${CROS_WORKON_SUBDIRS_TO_COPY[@]}"; do
		if [[ -d "${src}/${sl}" ]]; then
			mkdir -p "${dst}/${sl}"
			rsync -a --safe-links \
				--exclude-from=<(
					cd "${src}/${sl}" || \
						die "cd ${src}/${sl}"
					git ls-files --others --ignored --exclude-standard --directory 2>/dev/null | \
						sed 's:^:/:'
				) "${blacklist[@]}" "${src}/${sl}/" "${dst}/${sl}/" || \
				die "rsync -a --safe-links --exclude-from=<(...) ${blacklist[*]} ${src}/${sl}/ ${dst}/${sl}/"
		fi
	done
}

symlink_in_place() {
	local src="${1}"
	local dst="${2}"
	einfo "Using experimental inplace build in ${src}."

	SBOX_TMP=":${SANDBOX_WRITE}:"

	if [ "${SBOX_TMP/:$CROS_WORKON_SRCROOT://}" == "${SBOX_TMP}" ]; then
		ewarn "For inplace build you need to modify the sandbox"
		ewarn "Set SANDBOX_WRITE=${CROS_WORKON_SRCROOT} in your env."
	fi
	mkdir -p "${dst%/*}"
	ln -sf "${src}" "${dst}"
}

local_copy() {
	# Local vars used by all called functions.
	local src="${1}"
	local dst="${2}"

	# If we want to use git, and the source actually is a git repo
	if [ "${CROS_WORKON_INPLACE}" == "1" ]; then
		symlink_in_place "${src}" "${dst}"
	elif [ "${CROS_WORKON_OUTOFTREE_BUILD}" == "1" ]; then
		S="${src}"
	else
		local_copy_cp "${src}" "${dst}"
	fi
}

set_vcsid() {
	export VCSID="${PVR}-${1}"

	if [ "${CROS_WORKON_USE_VCSID}" = "1" ]; then
		append-cppflags -DVCSID=\'\"${VCSID}\"\'
		MAKEOPTS+=" VCSID=${VCSID}"
		# When working with multiple projects, keep from adding the same
		# flags many many times.
		CROS_WORKON_USE_VCSID="2"
	fi
}

get_rev() {
	GIT_DIR="$1" git rev-parse HEAD
}

cros-workon_src_unpack() {
	local fetch_method # local|git

	# Sanity check.  We cannot have S set to WORKDIR because if/when we try
	# to check out repos, git will die if it tries to check out into a dir
	# that already exists.  Some packages might try this when out-of-tree
	# builds are enabled, and they'll work fine most of the time because
	# they'll be using a full manifest and will just re-use the existing
	# checkout in src/platform/*.  But if the code detects that it has to
	# make its own checkout, things fall apart.  For out-of-tree builds,
	# the initial $S doesn't even matter because it resets it below to the
	# repo in src/platform/.
	if [[ ${S} == "${WORKDIR}" ]]; then
		die "Sorry, but \$S cannot be set to \$WORKDIR"
	fi

	# Set the default of CROS_WORKON_DESTDIR. This is done here because S is
	# sometimes overridden in ebuilds and we cannot rely on the global state
	# (and therefore ordering of eclass inherits and local ebuild overrides).
	: ${CROS_WORKON_DESTDIR:=${S}}

	# Fix array variables
	array_vars_autocomplete

	# Make sure all CROS_WORKON_DESTDIR are under S.
	local p
	for p in "${CROS_WORKON_DESTDIR[@]}"; do
		if [[ "${p}" != "${S}" && "${p}" != "${S}"/* ]]; then
			die "CROS_WORKON_DESTDIR=${p} must be under S=${S}"
		fi
	done

	if [[ "${PV}" == "9999" && "${CROS_WORKON_ALWAYS_LIVE}" != "1" ]] || [[ -z "${CROS_WORKON_PROJECT[*]}" ]]; then
		# Live / non-repo packages
		fetch_method=local
	elif [[ "${PV}" != "9999" && "${CROS_WORKON_ALWAYS_LIVE}" == "1" ]]; then
		die "CROS_WORKON_ALWAYS_LIVE is set for non-9999 ebuild"
	else
		fetch_method=git
	fi

	local repo=( "${CROS_WORKON_REPO[@]}" )
	local project=( "${CROS_WORKON_PROJECT[@]}" )
	local destdir=( "${CROS_WORKON_DESTDIR[@]}" )
	get_paths

	# Automatically build out-of-tree for common.mk packages.
	# TODO(vapier): Enable this once all common.mk packages have converted.
	#if [[ -e ${path}/common.mk ]] ; then
	#	: ${CROS_WORKON_OUTOFTREE_BUILD:=1}
	#fi

	if [[ ${fetch_method} == "git" && ${CROS_WORKON_OUTOFTREE_BUILD} == "1" ]] ; then
		# See if the local repo exists, is unmodified, and is checked out to
		# the right rev.  This will be the common case, so support it to make
		# builds a bit faster.
		if [[ -d ${path} ]] ; then
			if [[ ${CROS_WORKON_COMMIT} == "$(get_rev "${path}/.git")" ]] ; then
				local changes=$(
					cd "${path}"
					# Needed as `git status` likes to grab a repo lock.
					addpredict "${PWD}"
					# Ignore untracked files as they (should) be ignored by the build too.
					git status --porcelain | grep -v '^[?][?]'
				)
				if [[ -z ${changes} ]] ; then
					fetch_method=local
				else
					# Assume that if the dev has changes, they want it that way.
					: #ewarn "${path} contains changes"
				fi
			else
				ewarn "${path} is not at rev ${CROS_WORKON_COMMIT}"
			fi
		else
			# This will hit minilayout users a lot, and rarely non-minilayout
			# users.  So don't bother warning here.
			: #ewarn "${path} does not exist"
		fi
	fi

	if [[ "${fetch_method}" == "git" ]] ; then
		all_local() {
			local p
			for p in "${path[@]}"; do
				[[ -d ${p} ]] || return 1
			done
			return 0
		}

		local fetched=0
		if all_local; then
			for (( i = 0; i < project_count; ++i )); do
				# Looks like we already have a local copy of all repositories.
				# Let's use these and checkout ${CROS_WORKON_COMMIT}.
				#  -s: For speed, share objects between ${path} and ${S}.
				#  -n: Don't checkout any files from the repository yet. We'll
				#      checkout the source separately.
				#
				# We don't use git clone to checkout the source because the -b
				# option for clone defaults to HEAD if it can't find the
				# revision you requested. On the other hand, git checkout fails
				# if it can't find the revision you requested, so we use that
				# instead.

				# Destination directory. If we have one project, it's simply
				# ${CROS_WORKON_DESTDIR}. More projects either specify an array or go to
				# ${S}/${project}.

				if [[ "${CROS_WORKON_COMMIT[i]}" == "master" ]]; then
					# Since we don't have a CROS_WORKON_COMMIT revision specified,
					# we don't know what revision the ebuild wants. Let's take the
					# version of the code that the user has checked out.
					#
					# This almost replicates the pre-cros-workon behavior, where
					# the code you had in your source tree was used to build
					# things. One difference here, however, is that only committed
					# changes are included.
					#
					# TODO(davidjames): We should fix the preflight buildbot to
					# specify CROS_WORKON_COMMIT for all ebuilds, and update this
					# code path to fail and explain the problem.
					git clone -s "${path[i]}" "${destdir[i]}" || \
						die "Can't clone ${path[i]}."
					: $(( ++fetched ))
				else
					git clone -sn "${path[i]}" "${destdir[i]}" || \
						die "Can't clone ${path[i]}."
					if ! ( cd ${destdir[i]} && git checkout -q ${CROS_WORKON_COMMIT[i]} ) ; then
						ewarn "Cannot run git checkout ${CROS_WORKON_COMMIT[i]} in ${destdir[i]}."
						ewarn "Is ${path[i]} up to date? Try running repo sync."
						rm -rf "${destdir[i]}/.git"
					else
						: $(( ++fetched ))
					fi
				fi
			done
			if [[ ${fetched} -eq ${project_count} ]]; then
				# TODO: Id of all repos?
				# We should run get_rev in destdir[0] because CROS_WORKON_COMMIT
				# is only checked out there. Also, we can't use
				# CROS_WORKON_COMMIT directly because it could be a named or
				# abbreviated ref.
				set_vcsid "$(get_rev "${destdir[0]}/.git")"
				cros-workon_enforce_subtrees
				return
			else
				ewarn "Falling back to git.eclass..."
			fi
		fi

		EGIT_BRANCH="${CROS_WORKON_EGIT_BRANCH}"

		# Always pull all branches, if we are pulling source via git.
		EGIT_ALL_BRANCH="1"

		for (( i = 0; i < project_count; ++i )); do
			EGIT_REPO_URI="${repo[i]}/${project[i]}.git"
			EGIT_PROJECT="${project[i]}${CROS_WORKON_GIT_SUFFIX}"
			EGIT_SOURCEDIR="${destdir[i]}"
			EGIT_COMMIT="${CROS_WORKON_COMMIT[i]}"
			# Clones to /var, copies src tree to the /build/<board>/tmp.
			# Make sure git-2 does not run `unpack` for us automatically.
			# The normal cros-workon flow above doesn't do it, so don't
			# let git-2 do it either.  http://crosbug.com/38342
			EGIT_NOUNPACK=true git-2_src_unpack
			# TODO(zbehan): Support multiple projects for vcsid?
		done
		set_vcsid "${CROS_WORKON_COMMIT[0]}"
		cros-workon_enforce_subtrees
		return
	fi

	einfo "Using local source dir(s): ${path[*]}"

	# Clone from the git host + repository path specified by
	# CROS_WORKON_REPO + CROS_WORKON_PROJECT. Checkout source from
	# the branch specified by CROS_WORKON_COMMIT into the workspace path.
	# If the repository exists just punt and let it be copied off for build.
	if [[ "${fetch_method}" == "local" && ! -d ${path} ]] ; then
		ewarn "Sources are missing in ${path}"
		ewarn "You need to cros_workon and repo sync your project. For example if you are working on the crash-reporter package:"
		ewarn "cros_workon --board=amd64-generic start crash-reporter"
		ewarn "repo sync"
	fi

	einfo "path: ${path[*]}"
	einfo "destdir: ${destdir[*]}"
	# Copy source tree to /build/<board>/tmp for building
	for (( i = 0; i < project_count; ++i )); do
		local_copy "${path[i]}" "${destdir[i]}" || \
			die "Cannot create a local copy"
	done
	if [[ -n "${CROS_WORKON_PROJECT[*]}" ]]; then
		set_vcsid "$(get_rev "${path[0]}/.git")"
	fi
	cros-workon_enforce_subtrees
}

# Enforces subtree restrictions specified by CROS_WORKON_SUBTREE.
cros-workon_enforce_subtrees() {
	local i j p q

	local destdir=( "${CROS_WORKON_DESTDIR[@]}" )

	# If CROS_WORKON_OUTOFTREE_BUILD is enabled, CROS_WORKON_DESTDIR
	# can be outdated. In that case, S has been set to path[0] at this
	# point.
	if [[ "${CROS_WORKON_OUTOFTREE_BUILD}" == 1 ]]; then
		destdir=( "${S}" )
	fi

	# Gather the subtrees specified by CROS_WORKON_SUBTREE. All directories
	# and files under those subtrees are not blacklisted.
	local keep_dirs=()
	for (( i = 0; i < project_count; ++i )); do
		if [[ -z "${CROS_WORKON_SUBTREE[i]}" ]]; then
			keep_dirs+=( "${destdir[i]}" )
		else
			for p in ${CROS_WORKON_SUBTREE[i]}; do
				keep_dirs+=( "${destdir[i]}/${p}" )
			done
		fi
	done

	keep_dirs=( $(IFS=$'\n'; LC_ALL=C sort -u <<<"${keep_dirs[*]}") )

	# Ignore overlapping subtrees.
	for (( i = 0; i < ${#keep_dirs[@]}; ++i )); do
		p="${keep_dirs[i]}"
		: $(( j = i + 1 ))
		while (( j < ${#keep_dirs[@]} )); do
			q="${keep_dirs[j]}"
			if [[ "${q}" == "${p}"/* ]]; then
				einfo "Ignoring overlapping CROS_WORKON_SUBTREE: ${q} is under ${p}"
				keep_dirs=( "${keep_dirs[@]:0:j}" "${keep_dirs[@]:$(( j + 1 ))}" )
			else
				: $(( ++j ))
			fi
		done
	done

	# If the directory to keep is $S only, then there is nothing we need to do.
	if [[ "${#keep_dirs[@]}" == 1 && "${keep_dirs}" == "${S}" ]]; then
		return
	fi

	# It is an error to specify a missing file in CROS_WORKON_SUBTREE.
	for p in "${keep_dirs[@]}"; do
		if [[ ! -e "${p}" ]]; then
			die "File specified in CROS_WORKON_SUBTREE is missing: ${p}"
		fi
	done

	# Gather the parent directories of subtrees to use.
	# Those directories are exempted from blacklist because we need them to
	# reach subtrees.
	local keep_parents=()
	for p in "${keep_dirs[@]}"; do
		if [[ "${p}" == "${S}" ]]; then
			continue
		fi
		q="${p%/*}"
		while [[ "${q}" != "${S}" ]]; do
			keep_parents+=( "${q}" )
			q="${q%/*}"
		done
	done

	keep_parents=( $(IFS=$'\n'; LC_ALL=C sort -u <<<"${keep_parents[*]}") )

	# Construct arguments to pass to find(1) to list directories/files to
	# blacklist.
	#
	# The command line built here is tricky, but it does the following
	# during traversal of the filesystem by depth-first order:
	#
	#   1. Do nothing about the root directory ($S). Note that we should not
	#      reach here if there is nothing to blacklist.
	#   2. If the visiting file is a parent directory of a subtree (i.e. in
	#      $keep_parents[@]), then recurse into its contents.
	#   3. If the visiting file is the top directory of a subtree (i.e. in
	#      $keep_dirs[@]), then do not recurse into its contents.
	#   4. Otherwise, blacklist the visiting file, and if it is a directory,
	#      do not recursive into its contents.
	#
	local find_args=( "${S}" -mindepth 1 )
	for p in "${keep_parents[@]}"; do
		find_args+=( ! -path "${p}" )
	done
	find_args+=( -prune )
	for p in "${keep_dirs[@]}"; do
		find_args+=( ! -path "${p}" )
	done

	if [[ "${S}" == "${WORKDIR}"/* ]]; then
		# $S is writable, so just remove blacklisted files.
		find "${find_args[@]}" -exec rm -rf {} +
	else
		# $S is read-only, so use portage sandbox.
		local deny_paths="$(find "${find_args[@]}" -printf '%p:')"
		deny_paths="${deny_paths%:}"
		if [[ -n "${deny_paths}" ]]; then
			adddeny "${deny_paths}"
		fi
	fi
}

cros-workon_get_build_dir() {
	local dir
	if [[ ${CROS_WORKON_INCREMENTAL_BUILD} == "1" ]]; then
		dir="${SYSROOT}/var/cache/portage/${CATEGORY}/${PN}"
		local stripped_slot="${SLOT%%/*}"
		# We don't use the colon when adding in SLOTs because some tools
		# such as protoc interpret it as a special character in some
		# flags...
		[[ ${stripped_slot:-0} != "0" ]] && dir+="__${stripped_slot}"
	else
		dir="${WORKDIR}/build"
	fi
	echo "${dir}"
}

cros-workon_pkg_setup() {
	if [[ ${MERGE_TYPE} != "binary" && ${CROS_WORKON_INCREMENTAL_BUILD} == "1" ]]; then
		local out=$(cros-workon_get_build_dir)
		addwrite "${out}"
		mkdir -p -m 755 "${out}"
		chown ${PORTAGE_USERNAME}:${PORTAGE_GRPNAME} "${out}" "${out%/*}"
	fi
}

cros-workon_src_prepare() {
	local out="$(cros-workon_get_build_dir)"
	[[ ${CROS_WORKON_INCREMENTAL_BUILD} != "1" ]] && mkdir -p "${out}"
}

cros-workon_src_configure() {
	if [[ $(type -t cros-debug-add-NDEBUG) == "function" ]] ; then
		# Only run this if we've inherited cros-debug.eclass.
		cros-debug-add-NDEBUG
	fi

	if [[ -x ${ECONF_SOURCE:-.}/configure ]]; then
		econf "$@"
	else
		default
	fi
}

cros-workon_pkg_info() {
	print_quoted_array() { printf '"%s"\n' "$@"; }

	array_vars_autocomplete > /dev/null
	get_paths
	CROS_WORKON_SRCDIR=("${path[@]}")

	local val var
	for var in CROS_WORKON_SRCDIR CROS_WORKON_PROJECT ; do
		eval val=(\"\${${var}\[@\]}\")
		echo ${var}=\($(print_quoted_array "${val[@]}")\)
	done
}

EXPORT_FUNCTIONS pkg_setup src_unpack pkg_info
