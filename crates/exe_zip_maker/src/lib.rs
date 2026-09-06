//! Library supporting creating self-executable zip files.

use std::fs::{self, File};
use std::io::{self, BufReader, BufWriter, Read, Write};
use std::path::Path;

use sha2::{Digest, Sha256};

pub const BLOCK_SIZE: usize = 256 * 1024;
pub const PLACEHOLDER: &[u8] = b"%ZIP_HASH%";

/// Replaces all occurrences of `from` with `to` in `src`.
pub fn replace_bytes(src: &[u8], from: &[u8], to: &[u8]) -> Vec<u8> {
    if from.is_empty() {
        return src.to_vec();
    }
    let mut result = Vec::new();
    let mut i = 0;
    while i < src.len() {
        if src[i..].starts_with(from) {
            result.extend_from_slice(to);
            i += from.len();
        } else {
            result.push(src[i]);
            i += 1;
        }
    }
    result
}

/// Computes the SHA256 hex digest of the file at `path`.
pub fn compute_file_sha256_hex(path: &Path) -> io::Result<String> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; BLOCK_SIZE];
    loop {
        let n = file.read(&mut buffer)?;
        if n == 0 {
            break;
        }
        hasher.update(&buffer[..n]);
    }
    let digest = hasher.finalize();
    Ok(format!("{:x}", digest))
}

/// Creates a self-executable zip archive by prepending a preamble to a zip archive
/// and substituting `%ZIP_HASH%` with the SHA-256 hash of the zip archive.
pub fn create_exe_zip(preamble_path: &Path, zip_path: &Path, output_path: &Path) -> io::Result<()> {
    if let Some(parent) = output_path.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
        }
    }

    let zip_hash = compute_file_sha256_hex(zip_path)?;

    let preamble_content = fs::read(preamble_path)?;
    let modified_preamble = replace_bytes(&preamble_content, PLACEHOLDER, zip_hash.as_bytes());

    let mut out_file = BufWriter::with_capacity(BLOCK_SIZE, File::create(output_path)?);
    out_file.write_all(&modified_preamble)?;

    let zip_file = File::open(zip_path)?;
    let mut zip_reader = BufReader::with_capacity(BLOCK_SIZE, zip_file);
    io::copy(&mut zip_reader, &mut out_file)?;
    out_file.flush()?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let metadata = fs::metadata(output_path)?;
        let mut perms = metadata.permissions();
        perms.set_mode(perms.mode() | 0o111);
        fs::set_permissions(output_path, perms)?;
    }

    Ok(())
}
