use std::env;
use std::process;

fn main() {
    process::exit(shrubbery_lib::run_cli(env::args_os()));
}
