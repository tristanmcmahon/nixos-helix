#!/usr/bin/env bash

backup_source_classify() {
  local _root_type=$1 root_parent=$2 backup_type=$3 backup_parent=$4 backup_source=$5
  case $backup_type in
  nfs | nfs4 | cifs | smb3 | sshfs | fuse.sshfs)
    printf 'network:%s:%s\n' "$backup_type" "$backup_source"
    return 0
    ;;
  esac
  if [[ $backup_type == none || $backup_type == "" ]]; then
    printf 'unknown\n'
    return 1
  fi
  if [[ -n $root_parent && -n $backup_parent ]]; then
    if [[ $root_parent == "$backup_parent" ]]; then
      printf 'same-disk:%s\n' "$backup_parent"
      return 1
    fi
    printf 'separate-disk:%s\n' "$backup_parent"
    return 0
  fi
  printf 'unknown\n'
  return 1
}
