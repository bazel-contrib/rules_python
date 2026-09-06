use std::env;
use std::path::Path;
use std::process;

fn main() {
    let args: Vec<_> = env::args_os().collect();
    if args.len() != 4 {
        let prog_name = args
            .first()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_else(|| "exe_zip_maker".to_string());
        eprintln!("Usage: {} <preamble> <zip> <output>", prog_name);
        process::exit(1);
    }

    let preamble_path = Path::new(&args[1]);
    let zip_path = Path::new(&args[2]);
    let output_path = Path::new(&args[3]);

    if let Err(e) = exe_zip_maker_lib::create_exe_zip(preamble_path, zip_path, output_path) {
        eprintln!("exe_zip_maker: error: {}", e);
        process::exit(1);
    }
}
