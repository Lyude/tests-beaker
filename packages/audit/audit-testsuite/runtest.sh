#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/audit/Sanity/audit-testsuite
#   Description: Execute audit-testsuite
#   Author: Ondrej Moris <omoris@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2010 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include rhts environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/lib/beakerlib/beakerlib.sh || exit 1

PACKAGE="kernel"

# Optional test parametr - location of testuite git.
GIT_URL=${GIT_URL:-"https://github.com/linux-audit/audit-testsuite.git"}

# Optional test paramenter - branch containing tests.
GIT_BRANCH=${GIT_BRANCH:-"master"}

# Optional test parameter - list to tests to be executed.
TESTS=${TESTS:-""}

# Optional test parameter - debug mode.
DEBUG=${DEBUG:-""}

# Testing directory.
TEST_DIR=$(mktemp -d)

# Architecture.
ARCH=$(uname -m)

rlJournalStart

    rlPhaseStartSetup

        # Check requirements.
        rlCheckRpm "kernel"
        rlCheckRpm "git"
        rlCheckRpm "audit"
        rlCheckRpm "perl"
        rlIsFedora && rlCheckRpm "perl-Test"
        rlCheckRpm "perl-Test-Harness"
        rlCheckRpm "perl-File-Which"
        rlCheckRpm "perl-Time-HiRes"
        rlCheckRpm "libgcc"
        rlCheckRpm "expect"

        case $ARCH in
            "x86_64")
                rlCheckRpm "glibc-devel.i686"
                rlCheckRpm "libgcc.i686"
                ;;
            "s390x")
                rlCheckRpm "glibc-devel.s390"
                rlCheckRpm "libgcc.s390"
                ;;
            "ppc64le")
                rlCheckRpm "glibc-devel.ppc"
                rlCheckRpm "libgcc.ppc"
                ;;
            "ppc64")
                rlCheckRpm "glibc-devel.ppc"
                rlCheckRpm "libgcc.ppc"
                ;;
        esac

        # Download testsuite.
        rlRun "git clone $GIT_URL" 0
        if [ $? != 0 ]; then
            echo "Failed to git clone $GIT_URL." | tee -a $OUTPUTFILE
            rhts-report-result $TEST WARN $OUTPUTFILE
            rhts-abort -t recipe
        fi

        rlRun "pushd audit-testsuite" 0 || rlDie
        rlRun "git checkout $GIT_BRANCH" 0 || rlDie

        # Apply workarounds for beaker environment.
        rlRun "unset DISTRO" 0
        rlRun "echo $(id -u) >/proc/self/loginuid" 0

	# Turn off x86_64 specific test when running on non x86_64 architectures. 
	test "$(rlGetPrimaryArch)" != "x86_64" && \
	    rlRun "sed -i '/syscall_socketcall/d' tests/Makefile" 0
        
        # Initialize report.
        rlRun "echo 'Remote: $GIT_URL' >results.log" 0
        rlRun "echo 'Branch: $GIT_BRANCH' >>results.log" 0
        rlRun "echo 'Commit: $(git rev-parse HEAD)' >>results.log" 0
        rlRun "echo 'Kernel: $(uname -r)' >>results.log" 0
        rlRun "echo 'Auditd: $(rpm -q audit)' >>results.log" 0
        rlRun "echo '' >>results.log" 0
        
    rlPhaseEnd

    rlPhaseStartTest

        # Execute tests.
        if [[ -z "$TESTS" ]]; then
            TESTS=$(make list | grep -v make \
                              | grep -v "^$" \
                              | grep -v "Tests" \
                              | grep -v "====")

            # Test exec_name test (also) a feature not available until rhel8,
            # or compatible userspace package is needed for this test.
            auditctl -a always,exclude -F exe=/usr/bin/date
            if [ $? -eq 0 ]; then
                auditctl -d always,exclude -F exe=/usr/bin/date
                exclude_exe_filter_supported=1
            fi
            if rlIsRHEL "<8" || [ -z "$exclude_exe_filter_supported" ]; then
                TESTS="$(echo $TESTS | sed 's/exec_name//g')"
            fi

            # Test lost_reset is unstable.
            TESTS="$(echo $TESTS | sed 's/lost_reset//g')"

            TESTS=$(echo $TESTS | sed 's/  / /g')
        fi
        rlRun "TESTS=\"$TESTS\" unbuffer make -seC tests/ test >>results.log 2>&1" 0
        rlAssertGrep "Result: PASS" results.log
        rlRun "cat results.log" 0
        # DEBUG mode (interactive shell).
        [ -n "$DEBUG" ] && PS1="DEBUG: \W \$ " bash

    rlPhaseEnd

    rlPhaseStartCleanup

        # Submit report to beaker.
        rlFileSubmit "results.log" "audit-testsuite.results.$(uname -r).txt"

        # Clean-up.
        rlRun "popd" 0
        rlRun "rm -rf audit-testsuite" 0
    
    rlPhaseEnd

rlJournalPrintText

rlJournalEnd
