(* Yoann Padioleau
 *
 * Copyright (C) 2010 Facebook
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 * 
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)
open Common

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(*
 * The goal of this module is to provide a data-structure to represent
 * code "layers" (a.k.a. code "aspects"). The idea is to imitate google
 * earth layers (e.g. the wikipedia layer, panoramio layer, etc), but
 * for code. One could have a deadcode layer, a test coverage layer,
 * and then display those layers or not on an existing codebase in 
 * codemap. The layer is basically some mapping from files to a 
 * set of lines with a specific color code. 
 * 
 * 
 * A few design choices:
 * 
 *  - one could store such information directly into database_xxx.ml 
 *    and have pfff_db compute such information (for instance each function
 *    could have a set of properties like unit_test, or dead) but this 
 *    would force people to build their own db to visualize the results. 
 *    One could compute this information in database_light_xxx.ml, but this 
 *    will augment the size of the light db slowing down the codemap launch
 *    even when the people don't use the layers. So it's more flexible to just
 *    separate layer_code.ml from database_code.ml and have multiple persistent
 *    files for each information. Also it's quite convenient to have
 *    utilities like sgrep to be easily extendable to transform a query result
 *    into a layer.
 * 
 *  - How to represent a layer at the macro and micro level in codemap ?
 * 
 *    At the micro-level one has just to display the line with the
 *    requested color. At the macro-level have to either do a majority
 *    scheme or mixing scheme where for instance draw half of the 
 *    treemap rectangle in red and the other in green. 
 * 
 *    Because different layers could have different composition needs
 *    it is simpler to just have the layer say how it should be displayed
 *    at the macro_level. See the 'macro_level' field below.
 * 
 *  - how to have a layer data-structure that can cope with many
 *    needs ? 
 * 
 *   Here are some examples of layers and how they are "encoded" by the
 *   'layer' type below:
 * 
 *    * deadcode (dead function, dead class, dead statement, dead assignnements)
 * 
 *      How? dead lines in red color. At the macro_level one can give
 *      a grey_xxx color  with a percentage (e.g. grey53).
 * 
 *    * test coverage (static or dynamic)
 * 
 *      How? covered lines in green, not covered in red ? Also
 *      convey a GreyLevel visualization by setting the 'macro_level' field.
 * 
 *    * age of file
 * 
 *      How? 2010 in green, 2009 in yelow, 2008 in red and so on.
 *      At the macro_level can do a mix of colors.
 * 
 *    * bad smells
 * 
 *      How? each bad smell could have a different color and macro_level
 *      showing a percentage of the rectangle with the right color
 *      for each smells in the file.
 * 
 *    * security patterns (bad smells)
 * 
 *    * activity ? 
 * 
 *      How whow add and delete information ?
 *      At the micro_level can't show the delete, but at macro_level
 *      could divide the treemap_rectangle in 2 where percentage of
 *      add and delete, and also maybe white to show the amount of add
 *      and delete. Could also use my big circle scheme.
 *      How link to commit message ? TODO
 * 
 * 
 * later: 
 *  - could  associate more than just a color, e.g. a commit message when want
 *    to display a version-control layer, or some filling-patterns in
 *    addition to the color.
 *  - Could have  better precision than the line.
 * 
 * history:
 *  - I was writing some treemap generator specific for the deadcode
 *    analysis, the static coverage, the dynamic coverage, and the activity
 *    in a file (see treemap_php.ml). I was also offering different
 *    way to visualize the result (DegradeArchiColor | GreyLevel | YesNo).
 *    It was working fine but there was no easy way to combine 2
 *    visualisations, like the age "layer" and the "deadcode" layer
 *    to see correlations. Also adding simple layers like 
 *    visualizing all calls to HTML() or XHP was requiring to
 *    write another treemap generator. To be more generic and flexible require
 *    a real 'layer' type.
 *)

(*****************************************************************************)
(* Type *)
(*****************************************************************************)

(* note: the filenames must be in readable format so layer files can be reused
 * by multiple users.
 * 
 * alternatives:
 *  - could have line range ? useful for layer matching lots of
 *    consecutive lines in a file ?
 *  - todo? have more precision than just the line ? precise pos range ?
 * 
 *  - could for the lines instead of a 'kind' to have a 'count',
 *    and then some mappings from range of values to a color.
 *    For instance on a coverage layer one could say that from X to Y
 *    then choose this color, from Y to Z another color.
 *    But can emulate that by having a "coverage1", "coverage2"
 *    kind with the current scheme.
 * 
 *  - have a macro_level_composing_scheme: Majority | Mixed
 *    that is then interpreted in codemap instead of forcing
 *    the layer creator to specific how to show the micro_level
 *    data at the macro_level.
 *)

type layer = {
  files: (filename * file_info) list;
  kinds: (kind * Simple_color.emacs_color) list;
 }
 and file_info = {

   micro_level: (int (* line *) * kind) list;

   (* The list can be empty in which case codemap can use
    * the micro_level information and show a mix of colors.
    * 
    * The list can have just one element too and have a kind
    * different than the one used in the micro_level. For instance
    * for the coverage one can have red/green at micro_level
    * and grey_xxx at macro_level.
    *)
   macro_level: (kind * float (* percentage of rectangle *)) list;
 }
 (* ugly: because of the ugly way Ocaml.json_of_v currently works
  * the kind can not start with a uppercase
  *)
 and kind = string

 (* with tarzan *)


(* The filenames in the index are in absolute path format. That way they
 * can be used from codemap in hashtbl and compared to the
 * current file.
 *)
type layers_with_index = {
  root: Common.dirname;
  layers: (layer * bool (* is active *)) list;

  micro_index:
    (filename, (int, Simple_color.emacs_color) Hashtbl.t) Hashtbl.t;
  macro_index:
    (filename, (float * Simple_color.emacs_color) list) Hashtbl.t;
}

(*****************************************************************************)
(* Multi layers indexing *)
(*****************************************************************************)

(* Am I reinventing database indexing ? Should use a real database
 * to store layer information so one can then just use SQL to 
 * fastly get all the information relevant to a file and a line ?
 * I doubt MySQL can be as fast and light as my JSON + hashtbl indexing.
 *)
let build_index_of_layers ~root layers = 
  let hmicro = Common.hash_with_default (fun () -> Hashtbl.create 101) in
  let hmacro = Common.hash_with_default (fun () -> []) in
  
  layers +> List.iter (fun (layer, b) ->
    let hkind = Common.hash_of_list layer.kinds in

    layer.files +> List.iter (fun (file, finfo) ->

      let file = Filename.concat root file in

      (* todo? v is supposed to be a float representing a percentage of 
       * the rectangle but below we will add the macro info of multiple
       * layers together which mean the float may not represent percentage
       * anynore. They still represent a part of the file though.
       * The caller would have to first recompute the sum of all those
       * floats to recompute the actual multi-layer percentage.
       *)
      let color_macro_level = finfo.macro_level +> 
        Common.map_filter (fun (kind, v) ->
        try 
          Some (v, Hashtbl.find hkind kind)
        with
        Not_found -> 
          (* I was originally doing a failwith, but it can be convenient
           * to be able to filter kinds in codemap by just editing the
           * JSON file and removing certain kind definitions
           *)
          pr2_once (spf "PB: kind %s was not defined" kind);
          None
      ) 
      in
      hmacro#update file (fun old -> color_macro_level ++ old);

      finfo.micro_level +> List.iter (fun (line, kind) ->
        try 
          let color = Hashtbl.find hkind kind in

          hmicro#update file (fun oldh -> 
            (* We add so the same line could be assigned multiple colors.
             * The order of the layer could determine which color should
             * have priority.
             *)
            Hashtbl.add oldh line color;
            oldh
          )
        with Not_found ->
          pr2_once (spf "PB: kind %s was not defined" kind);
      )
    );
  );
  {
    layers = layers;
    root = root;
    macro_index = hmacro#to_h;
    micro_index = hmicro#to_h;
  }

(*****************************************************************************)
(* Meta *)
(*****************************************************************************)

(* generated by ocamltarzan *)

let vof_emacs_color s = Ocaml.vof_string s
let vof_filename s = Ocaml.vof_string s

let rec vof_layer { files = v_files; kinds = v_kinds } =
  let bnds = [] in
  let arg =
    Ocaml.vof_list
      (fun (v1, v2) ->
         let v1 = vof_kind v1
         and v2 = vof_emacs_color v2
         in Ocaml.VTuple [ v1; v2 ])
      v_kinds in
  let bnd = ("kinds", arg) in
  let bnds = bnd :: bnds in
  let arg =
    Ocaml.vof_list
      (fun (v1, v2) ->
         let v1 = vof_filename v1
         and v2 = vof_file_info v2
         in Ocaml.VTuple [ v1; v2 ])
      v_files in
  let bnd = ("files", arg) in let bnds = bnd :: bnds in Ocaml.VDict bnds
and
  vof_file_info { micro_level = v_micro_level; macro_level = v_macro_level }
                =
  let bnds = [] in
  let arg =
    Ocaml.vof_list
      (fun (v1, v2) ->
         let v1 = vof_kind v1
         and v2 = Ocaml.vof_float v2
         in Ocaml.VTuple [ v1; v2 ])
      v_macro_level in
  let bnd = ("macro_level", arg) in
  let bnds = bnd :: bnds in
  let arg =
    Ocaml.vof_list
      (fun (v1, v2) ->
         let v1 = Ocaml.vof_int v1
         and v2 = vof_kind v2
         in Ocaml.VTuple [ v1; v2 ])
      v_micro_level in
  let bnd = ("micro_level", arg) in
  let bnds = bnd :: bnds in Ocaml.VDict bnds
and vof_kind v = Ocaml.vof_string v

(*****************************************************************************)
(* Ocaml.v -> layer *)
(*****************************************************************************)

let emacs_color_ofv v = Ocaml.string_ofv v
let filename_ofv v = Ocaml.string_ofv v

let rec layer_ofv__ =
  let _loc = "Xxx.layer"
  in
    function
    | (Ocaml.VDict field_sexps as sexp) ->
        let files_field = ref None and kinds_field = ref None
        and duplicates = ref [] and extra = ref [] in
        let rec iter =
          (function
           | (field_name, field_sexp) :: tail ->
               ((match field_name with
                 | "files" ->
                     (match !files_field with
                      | None ->
                          let fvalue =
                            Ocaml.list_ofv
                              (function
                               | Ocaml.VList ([ v1; v2 ]) ->
                                   let v1 = filename_ofv v1
                                   and v2 = file_info_ofv v2
                                   in (v1, v2)
                               | sexp ->
                                   Ocaml.tuple_of_size_n_expected _loc 2 sexp)
                              field_sexp
                          in files_field := Some fvalue
                      | Some _ -> duplicates := field_name :: !duplicates)
                 | "kinds" ->
                     (match !kinds_field with
                      | None ->
                          let fvalue =
                            Ocaml.list_ofv
                              (function
                               | Ocaml.VList ([ v1; v2 ]) ->
                                   let v1 = kind_ofv v1
                                   and v2 = emacs_color_ofv v2
                                   in (v1, v2)
                               | sexp ->
                                   Ocaml.tuple_of_size_n_expected _loc 2 sexp)
                              field_sexp
                          in kinds_field := Some fvalue
                      | Some _ -> duplicates := field_name :: !duplicates)
                 | _ ->
                     if !Conv.record_check_extra_fields
                     then extra := field_name :: !extra
                     else ());
                iter tail)
           | [] -> ())
        in
          (iter field_sexps;
           if !duplicates <> []
           then Ocaml.record_duplicate_fields _loc !duplicates sexp
           else
             if !extra <> []
             then Ocaml.record_extra_fields _loc !extra sexp
             else
               (match ((!files_field), (!kinds_field)) with
                | (Some files_value, Some kinds_value) ->
                    { files = files_value; kinds = kinds_value; }
                | _ ->
                    Ocaml.record_undefined_elements _loc sexp
                      [ ((!files_field = None), "files");
                        ((!kinds_field = None), "kinds") ]))
    | sexp -> Ocaml.record_list_instead_atom _loc sexp
and layer_ofv sexp = layer_ofv__ sexp
and file_info_ofv__ =
  let _loc = "Xxx.file_info"
  in
    function
    | (Ocaml.VDict field_sexps as sexp) ->
        let micro_level_field = ref None and macro_level_field = ref None
        and duplicates = ref [] and extra = ref [] in
        let rec iter =
          (function
           | (field_name, field_sexp) :: tail ->
               ((match field_name with
                 | "micro_level" ->
                     (match !micro_level_field with
                      | None ->
                          let fvalue =
                            Ocaml.list_ofv
                              (function
                               | Ocaml.VList ([ v1; v2 ]) ->
                                   let v1 = Ocaml.int_ofv v1
                                   and v2 = kind_ofv v2
                                   in (v1, v2)
                               | sexp ->
                                   Ocaml.tuple_of_size_n_expected _loc 2 sexp)
                              field_sexp
                          in micro_level_field := Some fvalue
                      | Some _ -> duplicates := field_name :: !duplicates)
                 | "macro_level" ->
                     (match !macro_level_field with
                      | None ->
                          let fvalue =
                            Ocaml.list_ofv
                              (function
                               | Ocaml.VList ([ v1; v2 ]) ->
                                   let v1 = kind_ofv v1
                                   and v2 = Ocaml.float_ofv v2
                                   in (v1, v2)
                               | sexp ->
                                   Ocaml.tuple_of_size_n_expected _loc 2 sexp)
                              field_sexp
                          in macro_level_field := Some fvalue
                      | Some _ -> duplicates := field_name :: !duplicates)
                 | _ ->
                     if !Conv.record_check_extra_fields
                     then extra := field_name :: !extra
                     else ());
                iter tail)
           | [] -> ())
        in
          (iter field_sexps;
           if !duplicates <> []
           then Ocaml.record_duplicate_fields _loc !duplicates sexp
           else
             if !extra <> []
             then Ocaml.record_extra_fields _loc !extra sexp
             else
               (match ((!micro_level_field), (!macro_level_field)) with
                | (Some micro_level_value, Some macro_level_value) ->
                    {
                      micro_level = micro_level_value;
                      macro_level = macro_level_value;
                    }
                | _ ->
                    Ocaml.record_undefined_elements _loc sexp
                      [ ((!micro_level_field = None), "micro_level");
                        ((!macro_level_field = None), "macro_level") ]))
    | sexp -> Ocaml.record_list_instead_atom _loc sexp
and file_info_ofv sexp = file_info_ofv__ sexp
and kind_ofv__ = let _loc = "Xxx.kind" in fun sexp -> Ocaml.string_ofv sexp
and kind_ofv sexp = kind_ofv__ sexp


(*****************************************************************************)
(* Json *)
(*****************************************************************************)

let json_of_layer layer =
  layer +> vof_layer +> Ocaml.json_of_v

let layer_of_json json =
  json +> Ocaml.v_of_json +> layer_ofv

(*****************************************************************************)
(* Load/Save *)
(*****************************************************************************)

let is_json_filename filename = 
  filename =~ ".*\\.json$"
  (*
  match File_type.file_type_of_file filename with
  | File_type.PL (File_type.Web (File_type.Json)) -> true
  | _ -> false
  *)

(* we allow to save in JSON format because it may be useful to let
 * the user edit the layer file, for instance to adjust the colors.
 *)
let load_layer file =
  pr2 (spf "loading layer: %s" file);
  if is_json_filename file
  then Ocaml.load_json file +> layer_of_json
  else Common.get_value file

let save_layer layer file =
  if is_json_filename file
  (* layer +> vof_layer +> Ocaml.string_of_v +> Common.write_file ~file *)
  then layer +> json_of_layer +> Ocaml.save_json file
  else  Common.write_value layer file

(*****************************************************************************)
(* Layer builder helper *)
(*****************************************************************************)

(* Simple layer builder - group by file, by line, by property.
 * The layer can also be used to summarize statistics per dirs and
 * subdirs and so on.
 *)
let simple_layer_of_parse_infos ~root xs kinds =

  (* group by file, group by line, uniq categ *)
  let files_and_lines = xs +> List.map (fun (tok, kind) ->
    let file = Parse_info.file_of_info tok in
    let line = Parse_info.line_of_info tok in
    let file' = Common.relative_to_absolute file in 
    Common.filename_without_leading_path root file', (line, kind)
  )
  in

  let (group: (Common.filename * (int * kind) list) list) = 
    Common.group_assoc_bykey_eff files_and_lines 
  in

  { 
    kinds = kinds;
    files = group +> List.map (fun (file, lines_and_kinds) ->

      let (group: (int * kind list) list) = 
        Common.group_assoc_bykey_eff lines_and_kinds 
      in
      let all_kinds_in_file = 
        group +> List.map snd +> List.flatten +> Common.uniq in

      (file, { 
       micro_level = 
          group +> List.map (fun (line, kinds) -> 
            let kinds = Common.uniq kinds in
            kinds +> List.map (fun kind -> line, kind)
          ) +> List.flatten;

       macro_level =  
          (* todo: we are supposed to give a percentage per kind but
           * for now we give the same number to every kinds
           *)
          all_kinds_in_file +> List.map (fun kind -> (kind, 1.));
      })
    );
  }


(* old: superseded by Layer_code.layer.files and file_info 
 * type stat_per_file = 
 *  (string (* a property *), int list (* lines *)) Common.assoc
 * 
 * type stats = 
 *  (Common.filename, stat_per_file) Hashtbl.t
 *
 * 
 * old:
 * let (print_statistics: stats -> unit) = fun h ->
 * let xxs = Common.hash_to_list h in
 * pr2_gen (xxs);
 * ()
 *
 * let gen_security_layer xs = 
 * let _root = Common.common_prefix_of_files_or_dirs xs in
 * let files = Lib_parsing_php.find_php_files_of_dir_or_files xs in
 * 
 * let h = Hashtbl.create 101 in
 * 
 * files +> Common.index_list_and_total +> List.iter (fun (file, i, total) ->
 * pr2 (spf "processing: %s (%d/%d)" file i total);
 * let ast = Parse_php.parse_program file in
 * let stat_file = stat_of_program ast in
 * Hashtbl.add h file stat_file
 * );
 * Common.write_value h "/tmp/bigh";
 * print_statistics h
 *)

(*****************************************************************************)
(* Layer stat *)
(*****************************************************************************)

(* todo? could be useful also to show # of files involved instead of
 * just the line count.
 *)
let stat_of_layer layer =
  let h = Common.hash_with_default (fun () -> 0) in
  
  layer.kinds +> List.iter (fun (kind, _color) -> 
    h#add kind 0
  );
  layer.files +> List.iter (fun (file, finfo) ->
    finfo.micro_level +> List.iter (fun (_line, kind) ->
      h#update kind (fun old -> old + 1)
    )
  );
  h#to_list


let filter_layer f layer =
  { layer with 
    files = layer.files +> Common.filter (fun (file, _) -> f file);
  }
