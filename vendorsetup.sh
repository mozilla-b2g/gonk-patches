# Copyright (c) 2012, The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above
#       copyright notice, this list of conditions and the following
#       disclaimer in the documentation and/or other materials provided
#       with the distribution.
#     * Neither the name of Code Aurora Forum, Inc. nor the names of its
#       contributors may be used to endorse or promote products derived
#       from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED "AS IS" AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT
# ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS
# BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
# IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#
# Environment variables influencing operation:
#    B2G_TREE_ID - Defines the tree ID, used to determine which patches to
#        apply.  If unset, |treeid.sh| is run to identify the tree
#    B2G_PATCH_DIRS_OVERRIDE - List of patch directories to be used instead of
#        the build defaults.
#    B2G_USE_REPO - If set, use |repo manifest| to determine when the Android
#                   tree has changed.  Disabled by default for performance
#                   reasons.
#    REPO - Path to repo executable (default: repo)

# NOTE: This file is from changeset 3adb883a67f76736fae667ea48fb9159f616efd6
# retrieved from git://codeaurora.org/quic/b2g/build.git  

B2G_TREEID_SH=${B2G_TREEID_SH:-device/qcom/b2g_common/treeid.sh}
B2G_HASHED_FILES="${B2G_HASHED_FILES:-"device/qcom/b2g_common/vendorsetup.sh ${B2G_TREEID_SH}"}"
REPO="${REPO:-repo}"
B2G_PATCH_DIRS=${B2G_PATCH_DIRS_OVERRIDE:-device/qcom/b2g_common/patch}

__tree_md5sum()
{
   (
      FILELIST="$(find $@ -type f 2>/dev/null) ${B2G_HASHED_FILES}"
      if [[ -n "${B2G_USE_REPO}" ]]; then
         ${REPO} manifest -r -o - 2>/dev/null
      fi
      cat ${FILELIST}
   ) | openssl dgst -md5
}

__is_case_insensitive()
{
   F1='.validate_case_sensitive'
   F2='.VALIDATE_CASE_SENSITIVE'
   echo 'foo' > $F1
   echo 'bar' > $F2
   diff -q $F1 $F2 >/dev/null 2>&1
   RTN=$?
   rm -f $F1 $F2
   return $RTN
}

#
# Hack to work around following issue (bug 867259):
#   On case insensitive file systems, like Mac OS's HFS+, some files within
#   the linux kernel will appear to be modified in git.  This is due multiple
#   files having the same name exept for case differences.  This in turn
#   causes the patch process to error out due to "existing changes".  On
#   platforms without kernel patches, however, the build works fine in spite
#   of the file issues.  Therefore, workaround the problem by forcing the
#   known problem files to be the same in both content and name.
#
__kernel_case_insensitive_hack()
{
   if __is_case_insensitive ; then
      echo "  *** WARNING: case insensitive file system"
      if [[ -d .git ]]; then
         KERN_IGNORES="include/linux/netfilter/xt_CONNMARK.h"
         KERN_IGNORES="${KERN_IGNORES} include/linux/netfilter/xt_DSCP.h"
         KERN_IGNORES="${KERN_IGNORES} include/linux/netfilter/xt_MARK.h"
         KERN_IGNORES="${KERN_IGNORES} include/linux/netfilter/xt_RATEEST.h"
         KERN_IGNORES="${KERN_IGNORES} include/linux/netfilter/xt_TCPMSS.h"
         KERN_IGNORES="${KERN_IGNORES} include/linux/netfilter_ipv4/ipt_ECN.h"
         KERN_IGNORES="${KERN_IGNORES} include/linux/netfilter_ipv4/ipt_TTL.h"
         KERN_IGNORES="${KERN_IGNORES} include/linux/netfilter_ipv6/ip6t_HL.h"
         KERN_IGNORES="${KERN_IGNORES} net/ipv4/netfilter/ipt_ECN.c"
         KERN_IGNORES="${KERN_IGNORES} net/netfilter/xt_DSCP.c"
         KERN_IGNORES="${KERN_IGNORES} net/netfilter/xt_HL.c"
         KERN_IGNORES="${KERN_IGNORES} net/netfilter/xt_RATEEST.c"
         KERN_IGNORES="${KERN_IGNORES} net/netfilter/xt_TCPMSS.c"

         git add ${KERN_IGNORES}
         git commit -m "B2G hack for case insensitive FS." -q ${KERN_IGNORES}
      fi
   fi
}

__abandon_tree()
{
   rm -f out/lastpatch.md5sum
   if [[ -d .repo ]]; then
      ${REPO} abandon b2g_autogen_ephemeral_branch || true
   fi
}


__patch_tree()
{
   (
      cd $(gettop)
      local TREE_ID=${B2G_TREE_ID:-$(${B2G_TREEID_SH})}

      echo ">> Android tree IDs: ${TREE_ID}"
      set -e
      echo -n ">> Analyzing workspace for change..."
      local LASTMD5SUM=invalid
      local MD5SUM=unknown
      if [[ -f out/lastpatch.md5sum ]]; then
         LASTMD5SUM=$(cat out/lastpatch.md5sum)
         MD5SUM=$(__tree_md5sum ${B2G_PATCH_DIRS})
      fi
      if [[ "$LASTMD5SUM" != "$MD5SUM" ]]; then
         echo "Change detected.  Applying B2G patches".

         __abandon_tree

         branch() {
            [[ -d $1 ]] || return 1

            pushd $1 > /dev/null
            echo
            echo [entering $1]
            if [[ -d .git ]]; then
               # Try repo first, but if the project is not repo managed then
               # use a raw git branch instead.
               ${REPO} start b2g_autogen_ephemeral_branch .  ||
                 ( git checkout master && \
                   ( git branch -D b2g_autogen_ephemeral_branch || true ) && \
                   git branch b2g_autogen_ephemeral_branch && \
                   git checkout b2g_autogen_ephemeral_branch \
                 )
            else
               read -p "Project $1 is not managed by git. Modify anyway?  [y/N] "
               if [[ ${REPLY} != "y" ]]; then
                  echo "No."
                  popd > /dev/null
                  return 1
               fi
            fi
         }
         apply() {
            if [[ -d .git ]]; then
               git apply --index $1
            else
               patch -p1 < $1
            fi
         }
         git_rm() {
            if [[ -d .git ]]; then
               git rm -q $@
            else
               rm $@
            fi
         }
         git_add() {
            if [[ -d .git ]]; then
               git add $@
            fi
         }
         commit() {
            if [[ -d .git ]]; then
               git commit --all -m "B2G Adaptations" --allow-empty -q
            fi
            popd > /dev/null
         }

         # Find all of the patches for TREE_ID
         # and collate them into an associative array
         # indexed by project
         declare -a PRJ_LIST
         declare -a PATCH_LIST
         for DIR in ${B2G_PATCH_DIRS} ; do
            for ID in ${TREE_ID} ; do
               local D=${DIR}/${ID}
               [[ -d $D ]] || continue
               PATCHES=$(find $D -type f | sort -fs)
               for P in ${PATCHES}; do
                  PRJ=$(dirname ${P#${DIR}/${ID}/})
                  PATCH_ADDED=0
                  for (( I=0 ; I<${#PRJ_LIST[@]} ; I++ )) ; do
                     if [[ ${PRJ_LIST[$I]} == ${PRJ} ]]; then
                        PATCH_ADDED=1
                        PATCH_LIST[$I]="${PATCH_LIST[$I]} $P"
                        break
                     fi
                  done
                  if [[ ${PATCH_ADDED} -eq 0 ]]; then
                     PRJ_LIST=("${PRJ_LIST[@]}" "${PRJ}")
                     PATCH_LIST=("${PATCH_LIST[@]}" "$P")
                  fi
               done
            done
         done

         # Run through each project and apply patches
         ROOT_DIR=${PWD}
         for (( I=0 ; I<${#PRJ_LIST[@]} ; I++ )) ; do
            local PRJ=${PRJ_LIST[$I]}
            local FAILED_PRJ=${PRJ}
            set +e
            (
               set -e
               if branch ${PRJ} ; then
                  if [[ "$PRJ" == "kernel" ]]; then
                     __kernel_case_insensitive_hack
                  fi

                  if [[ $1 != "force" && $(whoami) != "lnxbuild" ]]; then
                     if [[ -n $(git status --porcelain) ]]; then
                        echo "ERROR: You have uncommited changes in ${PRJ}"
                        echo "You may force overwriting these changes"
                        echo "with |source build/envsetup.sh force|"
                        exit 1
                     fi
                  fi
                  # Ensure the project is clean before applying patches to it
                  git reset --hard HEAD > /dev/null
                  git clean -dfx

                  declare -a PATCHNAME
                  for P in ${PATCH_LIST[$I]} ; do
                     # Skip patches that have already been applied by an earlier ID
                     local PATCH_APPLIED=0
                     for APPLIED in ${PATCHNAME} ; do
                        if [[ ${APPLIED} == $(basename $P) ]]; then
                           PATCH_APPLIED=1
                        fi
                     done
                     if [[ ${PATCH_APPLIED} -eq 1 ]]; then
                        continue
                     else
                        PATCHNAME="${PATCHNAME} $(basename $P)"
                     fi

                     echo "  ${P}"
                     case $P in
                     *.patch)  apply ${ROOT_DIR}/$P ;;
                     *.sh)     source ${ROOT_DIR}/$P ;;
                     esac
                  done
                  commit
               fi
            )
            local ERR=$?
            if [[ ${ERR} -ne 0 ]]; then
               echo
               echo ERROR: Patching of ${FAILED_PRJ}/ failed.
               echo
               exit ${ERR}
            fi
            set -e
         done

         echo
         echo B2G patches applied.
         mkdir -p out
         echo $(__tree_md5sum ${B2G_PATCH_DIRS}) > out/lastpatch.md5sum
      else
         echo no changes detected.
      fi
   )
   ERR=$?

   if [[ ${ERR} -ne 0 ]]; then
      lunch() { echo ERROR: B2G PATCHES FAILED TO APPLY;  return 1; }
      choosecombo() { lunch; }
   fi
   return ${ERR}
}

# Stub out all java compilation.
export JAVA_HOME=$(gettop)/device/qcom/b2g_common/faketools/jdk
export ANDROID_JAVA_HOME=${JAVA_HOME}

# Use a local Xulrunner SDK copy instead of downloading
if [[ -d gaia/xulrunner-sdk/.git ]]; then
   export USE_LOCAL_XULRUNNER_SDK=1
fi

flash()
{
   ( cd $(gettop)/device/qcom/b2g_common && ./flash.sh $@ )
}

rungdb()
{
   ( cd $(gettop)/device/qcom/b2g_common && ./run-gdb.sh $@ )
}

if [[ -f vendor/qcom/proprietary/b2g_common/vendorsetup.sh ]]; then
   . vendor/qcom/proprietary/b2g_common/vendorsetup.sh
fi

if [[ -z $1 ]]; then
   __patch_tree
else
   case $1 in
   clean) __abandon_tree ;;
   force) __patch_tree force ;;
   np) echo "Skipping patch tree step...";;
   *) [[ -z "$PS1" ]] && __patch_tree || echo Error: Unknown command: $1
   esac
fi
