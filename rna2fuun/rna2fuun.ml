(* Module Rna2fuun
 *
 * Ocaml Rna to Fuun converter
 *)

open Printf
open Rna
open Parseintern

let usage () =
  fprintf stderr "usage not yet written, sorry";
  exit 1
	  
let _ =
  if Array.length Sys.argv != 2 then
    usage ();
  Parseintern.read_trace Sys.argv.(1)
