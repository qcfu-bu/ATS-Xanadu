(*
 * Sample ATS3 file for manually testing the LSP client (WS-0b).
 * Open this in the Extension Development Host to see the stub's hard-coded
 * warning squiggle over the first line.
 *
 * `val x: int = "hello"` is a deliberate type error that the *real* checker
 * (WS-1a/1b) will eventually flag; the stub ignores content and always warns
 * on line 1.
 *)

implement main0 () =
  let
    val x: int = "hello"  // intentional type error for later phases
  in
    ()
  end
