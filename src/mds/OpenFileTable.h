// -*- mode:C++; tab-width:8; c-basic-offset:2; indent-tabs-mode:t -*-
// vim: ts=8 sw=2 smarttab
/*
 * Ceph - scalable distributed file system
 *
 * Copyright (C) 2018 Red Hat
 *
 * This is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License version 2.1, as published by the Free Software
 * Foundation.  See file COPYING.
 *
 */

#ifndef OPEN_FILE_TABLE_H
#define OPEN_FILE_TABLE_H

#include "mdstypes.h"
#include "Anchor.h"

class CDir;
class CInode;
class MDSRank;
class MDSInternalContextBase;

class OpenFileTable
{
public:
  OpenFileTable(MDSRank *m) : mds(m) {}

  void add_inode(CInode *in);
  void remove_inode(CInode *in);
  void notify_link(CInode *in);
  void notify_unlink(CInode *in);
  bool is_any_dirty() const { return !dirty_items.empty(); }

  void commit(MDSInternalContextBase *c, uint64_t log_seq, int op_prio);
  uint64_t get_committed_log_seq() const { return committed_log_seq; }
  uint64_t get_committing_log_seq() const { return committing_log_seq; }
  bool is_any_committing() const { return num_pending_commit > 0; }

  void load(MDSInternalContextBase *c);
  bool is_loaded() const { return load_done; }
  void wait_for_load(MDSInternalContextBase *c) {
    assert(!load_done);
    waiting_for_load.push_back(c);
  }

  bool get_ancestors(inodeno_t ino, vector<inode_backpointer_t>& ancestors);

protected:
  MDSRank *mds;

  map<inodeno_t, Anchor> anchor_map;

  std::map<inodeno_t, unsigned> dirty_items; // ino -> dirty state
  static const unsigned DIRTY_NEW = 1;

  uint64_t committed_log_seq = 0;
  uint64_t committing_log_seq = 0;

  void get_ref(CInode *in);
  void put_ref(CInode *in);

  object_t get_object_name() const;

  bool clear_on_commit = false;
  unsigned num_pending_commit = 0;
  void _commit_finish(int r, uint64_t log_seq, MDSInternalContextBase *fin);

  map<inodeno_t, Anchor> loaded_anchor_map;
  list<MDSInternalContextBase*> waiting_for_load;
  bool load_done = false;

  void _load_finish(int op_r, int header_r, int values_r,
		    bool first, bool more,
                    bufferlist &header_bl,
		    std::map<std::string, bufferlist> &values);


  friend class C_IO_OFT_Load;
  friend class C_IO_OFT_Save;
};

#endif
