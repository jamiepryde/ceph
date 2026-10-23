#!/usr/bin/env bash
#
# Copyright (C) 2026 IBM <contact@redhat.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU Library Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Library Public License for more details.
#
# Coverage for the LRC "layer-plugin" profile key (tracker 81369). jerasure and
# isa diverge on later coding chunks, so the sub-plugin used for LRC layers must
# be recorded explicitly in the profile rather than inferred. These tests check
# that the monitor stamps the default (isa) into a profile that does not set it,
# preserves an explicit value, and that pools built on such profiles are usable.
#
# A *keyless* LRC profile can only arise on a cluster upgraded from before this
# fix: a patched monitor always stamps a value in (and re-stamps on --force), so
# it cannot be created here. Consequently the pool-create rejection
# (OSDMonitor::prepare_new_pool) and the OSD-side guards (OSD::load_pgs skips
# such PGs at boot, OSD::_make_pg aborts on the after-boot path) are NOT
# reachable from this test and are not currently covered by an automated test;
# exercising them needs an old-binary upgrade simulation. The shared decision
# they all use, ceph::lrc_profile_missing_layer_plugin(), is unit-tested in
# src/test/erasure-code/TestErasureCodeLrc.cc.
#
# This test asserts the monitor stamps layer-plugin=isa, so it only passes with
# the fix built in; do not backport it to branches that lack the fix.
#

source $CEPH_ROOT/qa/standalone/ceph-helpers.sh

function run() {
    local dir=$1
    shift

    export CEPH_MON="127.0.0.1:7160" # git grep '\<7160\>' : there must be only one
    export CEPH_ARGS
    CEPH_ARGS+="--fsid=$(uuidgen) --auth_cluster_required=none --auth_service_required=none --auth_client_required=none "
    CEPH_ARGS+="--mon-host=$CEPH_MON "

    setup $dir || return 1
    run_mon $dir a || return 1
    run_mgr $dir x || return 1
    for id in $(seq 0 9) ; do
        run_osd $dir $id || return 1
    done
    create_rbd_pool || return 1
    wait_for_clean || return 1

    local funcs=${@:-$(set | sed -n -e 's/^\(TEST_[0-9a-z_]*\) .*/\1/p')}
    for func in $funcs ; do
        $func $dir || return 1
    done

    teardown $dir || return 1
}

# An LRC profile created without layer-plugin is stamped with the isa default.
function TEST_layer_plugin_defaulted_to_isa() {
    local dir=$1
    local profile=lrc-default

    ceph osd erasure-code-profile set $profile \
        plugin=lrc k=4 m=2 l=3 \
        crush-failure-domain=osd || return 1
    ceph osd erasure-code-profile get $profile | \
        grep -q '^layer-plugin=isa$' || return 1

    ceph osd erasure-code-profile rm $profile || return 1
}

# An explicit layer-plugin is preserved, not overwritten by the default.
function TEST_layer_plugin_explicit_preserved() {
    local dir=$1
    local profile=lrc-jerasure

    ceph osd erasure-code-profile set $profile \
        plugin=lrc k=4 m=2 l=3 \
        layer-plugin=jerasure \
        crush-failure-domain=osd || return 1
    ceph osd erasure-code-profile get $profile | \
        grep -q '^layer-plugin=jerasure$' || return 1

    ceph osd erasure-code-profile rm $profile || return 1
}

# A pool built on a (defaulted) LRC profile activates and serves I/O.
function TEST_layer_plugin_pool_put_get() {
    local dir=$1
    local profile=lrc-pool-profile
    local poolname=lrc-pool

    ceph osd erasure-code-profile set $profile \
        plugin=lrc k=4 m=2 l=3 \
        crush-failure-domain=osd || return 1
    create_pool $poolname 12 12 erasure $profile || return 1
    wait_for_clean || return 1

    echo "layer-plugin-roundtrip" > $dir/ORIGINAL
    rados --pool $poolname put SOMETHING $dir/ORIGINAL || return 1
    rados --pool $poolname get SOMETHING $dir/COPY || return 1
    diff $dir/ORIGINAL $dir/COPY || return 1

    delete_pool $poolname || return 1
    ceph osd erasure-code-profile rm $profile || return 1
    rm -f $dir/ORIGINAL $dir/COPY
}

main test-erasure-code-lrc-layer-plugin "$@"

# Local Variables:
# compile-command: "cd ../.. ; make -j4 && \
#    qa/standalone/erasure-code/test-erasure-code-lrc-layer-plugin.sh"
# End:
