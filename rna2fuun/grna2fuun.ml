(* Module Rna2fuun
 *
 * Ocaml Rna to Fuun graphical hoscher
 *)

open Printf
open Rna
open Parseintern


type meta_instr = {
  mi_instr : rna_instr;
  mi_count : int;
  mi_rnaline : int;
}

type bm_mode =
    GM_BITMAP | GM_SRC | GM_DST

type gui = {
  mainWindow : GWindow.window;
  visual : Gdk.visual;
  mutable bitmapSelectorButtons : GButton.toggle_button array;
  mutable src_toggler : GButton.toggle_button;
  mutable dest_toggler : GButton.toggle_button;
  mutable rna_state : rna_state;
  instructions : meta_instr array;
  mutable currentPos : int;
  mutable currentBitmap : int;
  drawing : GDraw.drawable;
  update_status_fun : gui -> unit;
  mutable breakPoints : rna_instr list;
  mutable srcImg : Gdk.image option;
  mutable destImg : Gdk.image option;
  mutable bmMode : bm_mode;
}

let usage () =
  fprintf stderr "usage not yet written, sorry";
  exit 1

let gdkImage_from_gdkPixbuf gui pixbuf =
  let bytes = GdkPixbuf.get_pixels pixbuf
  and img = Gdk.Image.create ~kind:`FASTEST ~visual:gui.visual
    ~width:600 ~height:600
  and i = ref 0
  in
    for y = 0 to 599 do
      for x = 0 to 599 do
	Gdk.Image.put_pixel img ~x ~y
	  ~pixel:(Gdk.Truecolor.color_creator gui.visual
		     ~red:(256 * (Gpointer.get_byte bytes ~pos:!i))
		     ~green:(256 * (Gpointer.get_byte bytes ~pos:(!i + 1)))
		     ~blue:(256 * (Gpointer.get_byte bytes ~pos:(!i + 2))));
	i := !i + 3
      done
    done;
    img

let meta_instrs_from_rna_instrs = function
    [] -> []
  | x :: xs ->
      let rec work lnr result cur = function
	  [] -> cur :: result
	| x :: xs ->
	    if cur.mi_instr = x then
	      work (lnr + 1) result { cur with mi_count = cur.mi_count + 1 } xs
	    else
	      work (lnr + 1) (cur :: result)
		{ mi_rnaline = lnr; mi_instr = x; mi_count = 1 } xs
      in
	List.rev (work 2 [] { mi_rnaline = 1; mi_instr = x; mi_count = 1 } xs)

let displayBitmap gui bitmap darea =
  let image = Gdk.Image.create ~kind:`FASTEST ~visual:gui.visual
    ~width:600 ~height:600
  in
    for y = 0 to 599 do
      for x = 0 to 599 do
	let ((r,g,b), a) = bitmap.(y).(x)
	in
	  Gdk.Image.put_pixel image ~x:x ~y:y
	    ~pixel:(Gdk.Truecolor.color_creator gui.visual
		       ~red:(r*256) ~green:(g*256) ~blue:(b*256))
      done
    done;
    gui.drawing#put_image image ~x:0 ~y:0

let displayImage gui = function
  | Some img ->
      gui.drawing#put_image img ~x:0 ~y:0
  | None -> 
      fprintf stderr "failed to draw Gdk.Image :(\n";
      flush stderr

let displayPixBuf gui = function
  | Some pixbuf ->
      gui.drawing#put_pixbuf ~x:0 ~y:0 pixbuf
  | None ->
      fprintf stderr "failed to draw Gdk.PixBuf :(\n";
      flush stderr

let adjustImageSelectorButtons gui =
  let bitmap_nr = List.length gui.rna_state.bitmaps
  in
    begin
      match gui.bmMode with
	  GM_BITMAP ->
	    if gui.src_toggler#active then
	      gui.src_toggler#set_active false;
	    if gui.dest_toggler#active then
	      gui.dest_toggler#set_active false
	| GM_SRC ->
	    if not gui.src_toggler#active then
	      gui.src_toggler#set_active true;
	    if gui.dest_toggler#active then
	      gui.dest_toggler#set_active false
	| GM_DST ->
	    if gui.src_toggler#active then
	      gui.src_toggler#set_active false;
	    if not gui.dest_toggler#active then
	      gui.dest_toggler#set_active true
    end;
    if gui.currentBitmap >= bitmap_nr then
      gui.currentBitmap <- bitmap_nr - 1;
    for i = 0 to 9 do
      let b = gui.bitmapSelectorButtons.(i)
      in
	b#misc#set_sensitive (if i < bitmap_nr then true else false);
	if gui.bmMode != GM_BITMAP || (i != gui.currentBitmap && b#active) then
	  b#set_active false
	else
	  if gui.bmMode == GM_BITMAP &&
	    (i == gui.currentBitmap && (not b#active)) then
	    b#set_active true
    done

let update_gui gui () =
(*  displayDreck gui *)
  adjustImageSelectorButtons gui;
  begin
    match gui.bmMode with
      | GM_BITMAP ->
	  displayBitmap gui (List.nth gui.rna_state.bitmaps
				gui.currentBitmap) gui.drawing;
      | GM_SRC ->
	  displayImage gui gui.srcImg
      | GM_DST ->
	  displayImage gui gui.destImg
  end;
  gui.update_status_fun gui
    (*  displayBitmapManually gui (List.hd gui.rna_state.bitmaps) *)

let redraw_gui gui _ =
  update_gui gui ();
  false

let step ?(break=false) gui i () =
  let rec step_intern = function
      0 -> ()
    | i when break && 
	  (List.memq gui.instructions.(gui.currentPos).mi_instr
	      gui.breakPoints) ->
	()
    | i when gui.currentPos < Array.length gui.instructions ->
	let inst = gui.instructions.(gui.currentPos)
	in
	  for j = 1 to inst.mi_count
	  do
	    apply_instr gui.rna_state inst.mi_instr
	  done;
	  gui.currentPos <- gui.currentPos + 1;
	  step_intern (i - 1)
    | _ -> ()
  in
    step_intern i;
    update_gui gui ()

let breakpointChanged (combo : #GEdit.combo_box) gui () =
  gui.breakPoints <-
    [| []; [RI_Compose; RI_AddBitmap]; [RI_Compose]; [RI_AddBitmap];
       [RI_Clip]; [RI_Fill] |].(combo#active)

let setupGui (rna_instrs : rna_instr list) =
  let meta_instrs = Array.of_list (meta_instrs_from_rna_instrs rna_instrs)
  in let w = GWindow.window ~title:"grna2fuun"
    ~show:true ~width:1000 ~height:750 ()
    (* rest | cmdlist *)
  in let hb1 = GPack.hbox ~border_width:4 ~spacing:4 ~packing:w#add ()
    (* image notebook - small images - status - commands *)
  in let vbMain = GPack.vbox ~border_width:4 ~spacing:4 ~packing:hb1#add ()
    (* instr list container *)
  in let hbImgSelButs = GPack.hbox ~border_width:4 ~spacing:4
    ~packing:vbMain#add ()
  in let areaEventBox = GBin.event_box ~border_width:0
    ~width:600 ~height:600 ~packing:vbMain#add ()
  in let hbStatus = GPack.hbox ~border_width:4 ~spacing:4
    ~packing:vbMain#add ()
  in let hbCmd = GPack.hbox ~border_width:4 ~spacing:4
    ~packing:vbMain#add ()
  in let instrListBar = GRange.scrollbar `VERTICAL
    ~packing:(hb1#pack ~from:`END) ()
  in let instrList = GList.clist
    ~titles:["Number";"Count";"Command";"RNA-Line"]
    ~shadow_type:`OUT ~vadjustment:instrListBar#adjustment
    ~packing:(hb1#pack ~expand:true) ()
  in let reset = GButton.button ~label:"reset" ~packing:hbCmd#pack ()
  in let redraw = GButton.button ~label:"redraw" ~packing:hbCmd#pack ()
  in let plus1 = GButton.button ~label:"+1" ~packing:hbCmd#pack ()
  in let plus10 = GButton.button ~label:"+10" ~packing:hbCmd#pack ()
  in let plus100 = GButton.button ~label:"+100" ~packing:hbCmd#pack ()
  in let plus1000 = GButton.button ~label:"+1000" ~packing:hbCmd#pack ()
  in let plus10000 = GButton.button ~label:"+10000" ~packing:hbCmd#pack ()
  in let runto = GButton.button ~label:"Run to:" ~packing:hbCmd#pack ()
  in let (breakCombo, (_, breakComboColumn)) =
    GEdit.combo_box_text ~packing:hbCmd#pack 
      ~strings:["End" ; "Compose/AddBitmap" ; "Compose" ; "AddBitmap" ;
		"Clip" ; "Fill";] ()
  in let _ = GMisc.label ~text:"POS:" ~packing:hbStatus#pack ()
  in let posLabel = GMisc.label ~text:"?" ~packing:hbStatus#pack ()
  in let _ = GMisc.label ~text:"MARK:" ~packing:hbStatus#pack ()
  in let markLabel = GMisc.label ~text:"?" ~packing:hbStatus#pack ()
  in let _ = GMisc.label ~text:"DIR:" ~packing:hbStatus#pack ()
  in let dirLabel = GMisc.label ~text:"?" ~packing:hbStatus#pack ()
  in let _ = GMisc.label ~text:"BITMAPS:" ~packing:hbStatus#pack ()
  in let bitmapsLabel = GMisc.label ~text:"?" ~packing:hbStatus#pack ()
  in let statelistlenlabel = GMisc.label ~text:"RNAs:"
    ~packing:hbStatus#pack ()
  in let mouseCoordLabel = GMisc.label ~text:"Mouse()"
    ~packing:hbStatus#pack ()
  in let area = GMisc.drawing_area ~width:600 ~height:600
    ~packing:areaEventBox#add ()
  in let drawing = area#misc#realize (); new GDraw.drawable (area#misc#window)
  in let update_status gui =
    let rnaState = gui.rna_state
    in let posix, posiy = rnaState.Rna.position
    and markx, marky = rnaState.mark
    in
      instrList#select gui.currentPos 1;
      instrList#moveto (abs (gui.currentPos - 5)) 1;
      posLabel#set_text (sprintf "(%i,%i)" posix posiy);
      markLabel#set_text (sprintf "(%i,%i)" markx marky);
      dirLabel#set_text (string_of_dir rnaState.dir);
      bitmapsLabel#set_text (string_of_int (List.length rnaState.bitmaps));
      statelistlenlabel#set_text (sprintf "RNA: %i/%i"
				     gui.currentPos (Array.length meta_instrs))
  in let mouseMoveCB moEv =
    mouseCoordLabel#set_text (sprintf "Mouse(%i,%i)"
				 (int_of_float (GdkEvent.Motion.x moEv))
				 (int_of_float (GdkEvent.Motion.x moEv)));
       false
  in let gui = { mainWindow = w;
		 visual = w#misc#visual;
		 rna_state = createRNAState ();
		 instructions = meta_instrs;
		 currentPos = 0;
		 currentBitmap = 0;
		 drawing = drawing;
		 breakPoints = [];
		 bitmapSelectorButtons = [| |];
		 src_toggler = GButton.toggle_button ();
		 dest_toggler = GButton.toggle_button ();
		 update_status_fun = update_status;
		 srcImg = None;
		 destImg = None;
		 bmMode = GM_BITMAP;
  }
  in let select_bitmap nr () =
    if (nr != gui.currentBitmap &&
	gui.bitmapSelectorButtons.(nr)#active) then begin
      gui.bmMode <- GM_BITMAP;
      gui.currentBitmap <- nr;
      adjustImageSelectorButtons gui;
      update_gui gui ()
    end
  in let createBitmapSelectorButtons () =
    let a = Array.create 10 (GButton.toggle_button ())
    in
      for i = 0 to 9 do
	let b = GButton.toggle_button ~label:("BM"^(string_of_int i))
	  ~packing:hbImgSelButs#pack ()
	in
	  ignore (b#connect#toggled ~callback:(select_bitmap i));
	  a.(i) <- b
      done;
      a
  in let reset_gui () =
    gui.currentPos <- 0;
    gui.rna_state <- createRNAState ();
    update_gui gui ()
  in let goto_gui newPos =
    if newPos != gui.currentPos then begin
      reset_gui ();
      step gui newPos ();
      update_gui gui ()
    end
  in let mi_convert i e =
    ignore (instrList#append [string_of_int i;
			      string_of_int e.mi_count;
			      string_of_instr e.mi_instr;
                              string_of_int e.mi_rnaline])
  and srcdest_cb who what () =
    if who#active then
      begin
	if gui.bmMode != what then begin
	  gui.currentBitmap <- -1;
	  gui.bmMode <- what;
	  adjustImageSelectorButtons gui;
	  update_gui gui ()
	end
      end
  in
       begin
	 try
	   gui.srcImg <- Some (gdkImage_from_gdkPixbuf gui
				  (GdkPixbuf.from_file "source.png"))
	 with
	     _ ->
	       fprintf stderr "failed to load source.png\n"; flush stderr
       end;
    begin
      try
	gui.destImg <- Some (gdkImage_from_gdkPixbuf gui
				(GdkPixbuf.from_file "target.png"))
      with
	  _ ->
	    fprintf stderr "failed to load target.png\n"; flush stderr
    end;
    breakCombo#set_active 0;
    ignore (breakCombo#connect#changed (breakpointChanged breakCombo gui));
    gui.bitmapSelectorButtons <- createBitmapSelectorButtons ();
    gui.src_toggler <-
      GButton.toggle_button ~label:"SRC" ~packing:hbImgSelButs#pack ();
    ignore (gui.src_toggler#connect#clicked
	       ~callback:(srcdest_cb gui.src_toggler GM_SRC));
    gui.dest_toggler <-
      GButton.toggle_button ~label:"DST" ~packing:hbImgSelButs#pack ();
    ignore (gui.dest_toggler#connect#clicked
	       ~callback:(srcdest_cb gui.dest_toggler GM_DST));
    Array.iteri mi_convert meta_instrs;
    ignore (reset#connect#clicked ~callback:reset_gui);
    ignore (redraw#connect#clicked ~callback:(update_gui gui));
    ignore (plus1#connect#clicked ~callback:(step gui 1));
    ignore (plus10#connect#clicked ~callback:(step gui 10));
    ignore (plus100#connect#clicked ~callback:(step gui 100));
    ignore (plus1000#connect#clicked ~callback:(step gui 1000));
    ignore (plus10000#connect#clicked ~callback:(step gui 10000));
    ignore (areaEventBox#event#connect#motion_notify ~callback:mouseMoveCB);
    areaEventBox#event#add [`POINTER_MOTION];
    ignore (runto#connect#clicked ~callback:(step ~break:true gui max_int));
    ignore (area#event#connect#expose ~callback:(redraw_gui gui));
    ignore (w#connect#destroy ~callback:GMain.Main.quit);
    ignore (instrList#connect#select_row
	       ~callback:(fun ~row ~column ~event -> goto_gui row))

let _ =
  begin
    try
      ignore (GMain.init ());
    with
	x ->
	  fprintf stderr "are you sure you have an X server running?\n";
	  raise x
  end;
if Array.length Sys.argv != 2 then
    usage ();
  let statelist =
    try
      Parseintern.read_trace Sys.argv.(1);
    with
	x ->
	  fprintf stderr "parse error: %s\n" (Printexc.to_string x);
	  exit 2
  in
    setupGui statelist;
    (*
      Gdk.Rgb.init ();
      GtkBase.Widget.set_default_visual (Gdk.Rgb.get_visual ());
      GtkBase.Widget.set_default_colormap (Gdk.Rgb.get_cmap ());
    *)
    GMain.Main.main ()
(*  Parseintern.read_trace Sys.argv.(1); *)
