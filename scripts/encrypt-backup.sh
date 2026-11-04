#!/usr/bin/env bash
# Encrypt a backup archive and prove the result decrypts to a readable archive.
#
# Usage: scripts/encrypt-backup.sh <archive.tar.gz> <archive.tar.gz.enc>
#
# Environment:
#   BACKUP_ARCHIVE_PASSPHRASE   Passphrase (GitHub secret of the same name); never printed
#
# AES-256-CBC with a salted PBKDF2 key (200000 rounds). Decrypt with:
#   openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in <file>.enc -pass env:BACKUP_ARCHIVE_PASSPHRASE | tar -xzf -
set -euo pipefail

die() { echo "encrypt-backup: $*" >&2; exit 1; }

[ "$#" -eq 2 ] || die "usage: $0 <archive.tar.gz> <archive.tar.gz.enc>"
[ -s "$1" ] || die "archive is missing or empty: $1"
[ -n "${BACKUP_ARCHIVE_PASSPHRASE:-}" ] || die "BACKUP_ARCHIVE_PASSPHRASE is not configured"

openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 \
  -in "$1" \
  -out "$2" \
  -pass env:BACKUP_ARCHIVE_PASSPHRASE
[ -s "$2" ] || die "encryption produced no output"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -in "$2" \
  -pass env:BACKUP_ARCHIVE_PASSPHRASE | tar -tzf - >/dev/null ||
  die "the encrypted file does not decrypt to a readable archive"
