use std::env;
use std::process;

fn main() {
    process::exit(rupyru_box_lib::run_cli(env::args_os()));
}
