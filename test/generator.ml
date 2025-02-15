(***********************************************************************)
(*                                                                     *)
(*                      The PRINGO library                             *)
(*                                                                     *)
(*            Xavier Leroy, projet Gallium, INRIA Paris                *)
(*                                                                     *)
(*  Copyright 2017 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License v2,      *)
(*  with the special exception on linking described in file LICENSE.   *)
(*                                                                     *)
(***********************************************************************)

(* Testing PRNGs using the Dieharder statistical tests,
   http://webhome.phy.duke.edu/~rgb/General/dieharder.php *)

let seed = ref "Jamais un coup de dés n'abolira le hasard. -Mallarmé"

module type TEST = sig
  val gen_bytes: unit -> unit
  val gen_int32: unit -> unit
  val gen_int64: unit -> unit
  val gen_blocks: int -> unit
  val treesplits: int -> unit
  val laggedsplit: int -> unit
end

module Maketest (R: PRNG.STATE) : TEST = struct

let init () = R.seed !seed

let out8 g =
  output_byte stdout (R.byte g)

let out32 g =
  let n = R.bits32 g in
  output_byte stdout (Int32.to_int n);
  output_byte stdout (Int32.(to_int (shift_right_logical n 8)));
  output_byte stdout (Int32.(to_int (shift_right_logical n 16)));
  output_byte stdout (Int32.(to_int (shift_right_logical n 24)))

let out64 g =
  let n = R.bits64 g in
  output_byte stdout (Int64.to_int n);
  output_byte stdout (Int64.(to_int (shift_right_logical n 8)));
  output_byte stdout (Int64.(to_int (shift_right_logical n 16)));
  output_byte stdout (Int64.(to_int (shift_right_logical n 24)));
  output_byte stdout (Int64.(to_int (shift_right_logical n 32)));
  output_byte stdout (Int64.(to_int (shift_right_logical n 40)));
  output_byte stdout (Int64.(to_int (shift_right_logical n 48)));
  output_byte stdout (Int64.(to_int (shift_right_logical n 56)))

(* Generate byte per byte on stdout *)

let gen_bytes () =
  let g = init() in while true do out8 g done

(* Generate using 32-bit integers *)

let gen_int32 () =
  let g = init() in while true do out32 g done

(* Generate using 64-bit integers *)

let gen_int64 () =
  let g = init() in while true do out64 g done

(* Generate using N-byte blocks *)

let gen_blocks n =
  let g = init() in
  let b = Bytes.create n in
  while true do
    R.bytes g b 0 n;
    output stdout b 0 n
  done

(* Tree of splits.  Produce 2^N generators then interleave their outputs *)

let treesplits n =
  let rec mkgens n g =
    if n <= 0 then [g] else begin
      let g' = R.split g in
      mkgens (n-1) g @ mkgens (n-1) g'
    end in
  let gl = mkgens n (init()) in
  while true do List.iter out32 gl done

(* Lagged split.  Split, then produce N numbers with the original RNG, then
   switch to the splitted RNG and repeat.  *)

let laggedsplit n =
  let rec lag g =
    let g' = R.split g in
    for _i = 1 to n do out32 g done;
    lag g'
  in lag (init())

end

module T1 = Maketest(PRNG.Splitmix.State)
module T2 = Maketest(PRNG.Chacha.State)
module T3 = Maketest(PRNG.LXM.State)

let dut = ref (module T1 : TEST)

let gen_bytes () =
  let module T = (val !dut) in T.gen_bytes()
let gen_int32 () =
  let module T = (val !dut) in T.gen_int32()
let gen_int64 () =
  let module T = (val !dut) in T.gen_int64()
let gen_blocks n =
  let module T = (val !dut) in T.gen_blocks n
let treesplits n =
  let module T = (val !dut) in T.treesplits n
let laggedsplit n =
  let module T = (val !dut) in T.laggedsplit n

let run_config s =
  let l =
    match String.split_on_char '-' s with
    | "splitmix" :: l -> dut := (module T1 : TEST); l
    | "chacha" :: l -> dut := (module T2 : TEST); l
    | "lxm" :: l -> dut := (module T3 : TEST); l
    | _ -> raise (Arg.Bad ("unknown configuration " ^ s)) in
  match l with
  | ["seq8"] -> gen_bytes()
  | ["seq32"] -> gen_int32()
  | ["seq64"] -> gen_int64()
  | ["block"; n] -> gen_blocks (int_of_string n)
  | ["treesplit"; n] -> treesplits (int_of_string n)
  | ["laggedsplit"; n] -> laggedsplit (int_of_string n)
  | _ -> raise (Arg.Bad ("unknown configuration " ^ s))

let _ =
  Arg.(parse [
    "-splitmix", Unit (fun () -> dut := (module T1 : TEST)),
      " Test the Splitmix implementation";
    "-chacha", Unit (fun () -> dut := (module T2 : TEST)),
      " Test the Chacha implementation";
    "-lxm", Unit (fun () -> dut := (module T3 : TEST)),
      " Test the LXM implementation";
    "-seed", Set_string seed,
      " <seed>  Choose a seed";
    "-seq8", Unit gen_bytes,
      " Produce 8-bit numbers sequentially";
    "-seq32", Unit gen_int32,
      " Produce 32-bit numbers sequentially";
    "-seq64", Unit gen_int64,
      " Produce 64-bit numbers sequentially";
    "-block", Int gen_blocks,
      " <n>  Produce n-byte blocks sequentially";
    "-treesplit", Int treesplits,
      " <n>  Perform 2^n splits then round robin between them";
    "-laggedsplit", Int laggedsplit,
      " <n>  Split, produce n 32-bit numbers, then use the split"
  ]
  run_config
  "Usage: ./generator <options> [config] | dieharder -a -g 200.\nOptions are:")

