open! Base
open! Scad_ml

let base_endpoints ~height hand (w : Wall.t) =
  let top, bot =
    match hand with
    | `Left  -> `TL, `BL
    | `Right -> `TR, `BR
  in
  [ Points.get w.foot bot
  ; Points.get w.foot top
  ; Wall.(Edge.point_at_z (Edges.get w.edges top) height)
  ; Wall.(Edge.point_at_z (Edges.get w.edges bot) height)
  ]

let base_steps ~n_steps starts dests =
  let norms = List.map2_exn ~f:(fun s d -> Vec3.(norm (s <-> d))) starts dests in
  let lowest_norm = List.fold ~init:Float.max_value ~f:Float.min norms in
  let adjust norm = Float.(to_int (norm /. lowest_norm *. of_int n_steps)) in
  `Ragged (List.map ~f:adjust norms)

let bez_base ?(height = 11.) ?(n_steps = 6) (w1 : Wall.t) (w2 : Wall.t) =
  let ((dx, dy, _) as dir1) = Wall.foot_direction w1
  and dir2 = Wall.foot_direction w2 in
  let mask = if Float.(abs dx > abs dy) then 1., 0., 0. else 0., 1., 0. in
  let get_bez start dest =
    let diff = Vec3.(dest <-> start) in
    let p1 = Vec3.(start <+> mul dir1 (0.01, 0.01, 0.)) (* fudge for union *)
    and p2 = Vec3.(start <+> mul mask diff)
    and p3 = Vec3.(dest <-> mul dir2 (0.01, 0.01, 0.)) in
    Bezier.quad_vec3 ~p1 ~p2 ~p3
  in
  let starts = base_endpoints ~height `Right w1 in
  let dests = base_endpoints ~height `Left w2 in
  let steps = base_steps ~n_steps starts dests
  and bezs = List.map2_exn ~f:get_bez starts dests in
  Bezier.prism_exn bezs steps

let cubic_base
    ?(height = 4.)
    ?(scale = 1.1)
    ?(d = 2.)
    ?(n_steps = 10)
    (w1 : Wall.t)
    (w2 : Wall.t)
  =
  let dir1 = Wall.foot_direction w1
  and dir2 = Wall.foot_direction w2
  and dist = d, d, 0.
  and width = Vec3.(norm (w1.foot.top_right <-> w1.foot.bot_right)) *. scale in
  let get_bez top start dest =
    let outward = if top then Vec3.add (width, width, 0.) dist else dist in
    let p1 = Vec3.(start <+> mul dir1 (0.01, 0.01, 0.)) (* fudge for union *)
    and p2 = Vec3.(start <-> mul dir1 outward)
    and p3 = Vec3.(dest <+> mul dir2 outward)
    and p4 = Vec3.(dest <-> mul dir2 (0.01, 0.01, 0.)) in
    Bezier.cubic_vec3 ~p1 ~p2 ~p3 ~p4
  in
  let starts = base_endpoints ~height `Right w1 in
  let dests = base_endpoints ~height `Left w2 in
  let steps = base_steps ~n_steps starts dests
  and bezs = List.map3_exn ~f:get_bez [ false; true; true; false ] starts dests in
  Bezier.prism_exn bezs steps

let snake_base
    ?(height = 4.)
    ?(scale = 1.5)
    ?(d = 2.)
    ?(n_steps = 10)
    (w1 : Wall.t)
    (w2 : Wall.t)
  =
  let dir1 = Wall.foot_direction w1
  and dir2 = Wall.foot_direction w2
  and dist = d, d, 0.
  and width = Vec3.(norm (w1.foot.top_right <-> w1.foot.bot_right)) *. scale in
  let get_bez top start dest =
    let outward = Vec3.add (width, width, 0.) dist in
    let p1 = Vec3.(start <+> mul dir1 (0.01, 0.01, 0.)) (* fudge for union *)
    and p2 = Vec3.(start <-> mul dir1 (if top then dist else outward))
    and p3 = Vec3.(dest <+> mul dir2 (if top then outward else dist))
    and p4 = Vec3.(dest <-> mul dir2 (0.01, 0.01, 0.)) in
    Bezier.cubic_vec3 ~p1 ~p2 ~p3 ~p4
  in
  let starts = base_endpoints ~height `Right w1 in
  let dests = base_endpoints ~height `Left w2 in
  let steps = base_steps ~n_steps starts dests
  and bezs = List.map3_exn ~f:get_bez [ false; true; true; false ] starts dests in
  Bezier.prism_exn bezs steps

let inward_elbow_base ?(height = 11.) ?(n_steps = 6) (w1 : Wall.t) (w2 : Wall.t) =
  (* Quad bezier, but starting from the bottom (inside face) of the wall and
   * projecting inward. This is so similar to bez_base that some generalization may
   * be possible to spare the duplication. Perhaps an option of whether the start is
   * the inward face (on the right) or the usual CW facing right side. *)
  let dir1 = Wall.foot_direction w1
  and dir2 = Wall.foot_direction w2
  and ((inx, iny, _) as inward_dir) =
    Vec3.normalize Vec3.(w1.foot.bot_right <-> w1.foot.top_right)
  in
  let mask = if Float.(abs inx > abs iny) then 1., 0., 0. else 0., 1., 0. in
  let get_bez start dest =
    let diff = Vec3.(dest <-> start) in
    let p1 = Vec3.(start <-> mul inward_dir (0.01, 0.01, 0.)) (* fudge for union *)
    and p2 = Vec3.(start <+> mul mask diff)
    and p3 = Vec3.(dest <-> mul dir2 (0.01, 0.01, 0.)) in
    Bezier.quad_vec3 ~p1 ~p2 ~p3
  in
  let starts =
    let up_bot = Wall.Edge.point_at_z w1.edges.bot_right height in
    let w = Vec3.(norm (w1.foot.bot_right <-> w1.foot.top_right)) in
    let slide p = Vec3.(add p (mul dir1 (w, w, 0.))) in
    [ slide w1.foot.bot_right; w1.foot.bot_right; up_bot; slide up_bot ]
  and dests = base_endpoints ~height `Left w2 in
  let steps = base_steps ~n_steps starts dests
  and bezs = List.map2_exn ~f:get_bez starts dests in
  Bezier.prism_exn bezs steps

let straight_base ?(height = 11.) ?(fudge_factor = 6.) (w1 : Wall.t) (w2 : Wall.t) =
  let ((dx, dy, _) as dir1) = Wall.foot_direction w1
  and dir2 = Wall.foot_direction w2 in
  let major_diff, minor_diff =
    let x, y, _ =
      Vec3.(
        mean [ w1.foot.bot_right; w1.foot.top_right ]
        <-> mean [ w2.foot.bot_left; w2.foot.top_left ])
    in
    if Float.(abs dx > abs dy) then x, y else y, x
  in
  let fudge d =
    (* For adjustment of bottom (inside face) points to account for steep angles
     * that would otherwise cause the polyhedron to fail. Distance moved is a
     * function of how far apart the walls are along the major axis of the first. *)
    let extra =
      if Float.(abs minor_diff > abs major_diff)
      then Float.(abs (min (abs major_diff -. fudge_factor) 0.))
      else 0.
    in
    Vec3.(add (mul d (extra, extra, 0.)))
  and overlap =
    let major_ax = if Float.(abs dx > abs dy) then dx else dy in
    if not Float.(Sign.equal (sign_exn major_diff) (sign_exn major_ax))
    then Float.abs major_diff
    else 0.01
  (* If the walls are overlapping, move back the start positions to counter. *)
  and outward =
    (* away from the centre of mass, or not? *)
    Float.(
      Vec3.(norm @@ (w1.foot.top_right <-> w2.foot.top_left))
      > Vec3.(norm @@ (w1.foot.top_right <-> w2.foot.bot_left)))
  in
  let starts =
    let up_bot = Wall.Edge.point_at_z w1.edges.bot_right height in
    [ (if not outward then fudge dir1 w1.foot.bot_right else w1.foot.bot_right)
    ; w1.foot.top_right
    ; Wall.Edge.point_at_z w1.edges.top_right height
    ; (if not outward then fudge dir1 up_bot else up_bot)
    ]
    |> List.map ~f:Vec3.(add (mul dir1 (overlap, overlap, 0.)))
  and dests =
    let up_top = Wall.Edge.point_at_z w2.edges.top_left height
    and up_bot = Wall.Edge.point_at_z w2.edges.bot_left height
    and slide = fudge (Vec3.negate dir2) in
    [ (if outward then slide w2.foot.bot_left else w2.foot.bot_left)
    ; w2.foot.top_left
    ; up_top
    ; (if outward then slide up_bot else up_bot)
    ]
    |> List.map ~f:Vec3.(add (mul dir2 (-0.05, -0.05, 0.)))
  in
  Util.prism_exn starts dests

let join_walls ?(n_steps = 6) ?(fudge_factor = 3.) (w1 : Wall.t) (w2 : Wall.t) =
  let ((dx, dy, _) as dir1) = Wall.foot_direction w1
  and dir2 = Wall.foot_direction w2 in
  let major_diff, minor_diff =
    let x, y, _ =
      Vec3.(
        mean [ w1.foot.bot_right; w1.foot.top_right ]
        <-> mean [ w2.foot.bot_left; w2.foot.top_left ])
    in
    if Float.(abs dx > abs dy) then x, y else y, x
  in
  (* Move the destination points along the outer face of the wall to improve angle. *)
  let fudge =
    let extra =
      if Float.(abs minor_diff > fudge_factor)
      then Float.(abs (min (abs major_diff -. fudge_factor) 0.))
      else 0.
    in
    Vec3.(add (mul dir2 (-.extra, -.extra, 0.)))
  and overlap =
    let major_ax = if Float.(abs dx > abs dy) then dx else dy in
    if not Float.(Sign.equal (sign_exn major_diff) (sign_exn major_ax))
    then Float.abs major_diff
    else 0.01
    (* If the walls are overlapping, move back the start positions to counter. *)
  in
  let starts =
    Bezier.curve_rev
      ~n_steps
      ~init:(Bezier.curve ~n_steps w1.edges.bot_right)
      w1.edges.top_right
    |> List.map ~f:Vec3.(add (mul dir1 (overlap, overlap, 0.)))
  and dests =
    Bezier.curve_rev ~n_steps ~init:(Bezier.curve ~n_steps w2.edges.bot_left) (fun step ->
        fudge @@ w2.edges.top_left step )
    |> List.map ~f:Vec3.(add (mul dir2 (-0.01, -0.01, 0.)))
  and wedge =
    (* Fill in the volume between the "wedge" hulls that are formed by swinging the
     * key face prior to drawing the walls. *)
    Util.prism_exn
      (List.map
         ~f:Vec3.(add (mul (Wall.start_direction w1) (overlap, overlap, overlap)))
         [ w1.start.top_right; w1.edges.bot_right 0.; w1.edges.top_right 0.0001 ] )
      (List.map
         ~f:Vec3.(add (mul (Wall.start_direction w2) (-0.01, -0.01, -0.01)))
         [ w2.start.top_left; w2.edges.bot_left 0.; fudge @@ w2.edges.top_left 0.0001 ] )
  in
  Model.union [ Util.prism_exn starts dests; wedge ]

module Body = struct
  module Cols = struct
    type col =
      { north : Wall.t option
      ; south : Wall.t option
      }

    type t = col Map.M(Int).t

    let make
        ?(d1 = 2.)
        ?(d2 = 5.)
        ?(z_off = 0.)
        ?(thickness = 3.5)
        ?(n_steps = `Flat 4)
        ?(north_lookup = fun _ -> true)
        ?(south_lookup = fun i -> i > 1)
        Plate.{ config = { spacing; _ }; columns; _ }
      =
      (* TODO: leaving these as params since I may want to adjust d1 based on z.
       * Still have to decide if I want to do it here or in poly_siding *)
      let bez_wall ~d1 ~d2 =
        Wall.column_drop ~spacing ~columns ~z_off ~d1 ~d2 ~thickness ~n_steps
      in
      Map.mapi
        ~f:(fun ~key:i ~data:_ ->
          { north = (if north_lookup i then Some (bez_wall ~d1 ~d2 `North i) else None)
          ; south = (if south_lookup i then Some (bez_wall ~d1 ~d2 `South i) else None)
          } )
        columns

    let col_to_scad col =
      Model.union
        (List.filter_map ~f:(Option.map ~f:Wall.to_scad) [ col.north; col.south ])

    let to_scad t =
      Model.union (Map.fold ~init:[] ~f:(fun ~key:_ ~data l -> col_to_scad data :: l) t)
  end

  module Sides = struct
    type t =
      { west : Wall.t Map.M(Int).t
      ; east : Wall.t Map.M(Int).t
      }

    let make
        ?(d1 = 2.)
        ?(d2 = 5.)
        ?(z_off = 0.)
        ?(thickness = 3.5)
        ?(n_steps = `Flat 4)
        ?(west_lookup = fun i -> i = 0)
        ?(east_lookup = fun _ -> false)
        Plate.{ columns; _ }
      =
      let west_col = Map.find_exn columns 0
      and _, east_col = Map.max_elt_exn columns in
      let sider side ~key ~data m =
        let lookup =
          match side with
          | `West -> west_lookup
          | `East -> east_lookup
        in
        if lookup key
        then (
          let data = Wall.poly_siding ~d1 ~d2 ~z_off ~thickness ~n_steps `West data in
          Map.add_exn ~key ~data m )
        else m
      in
      { west = Map.fold ~init:(Map.empty (module Int)) ~f:(sider `West) west_col.keys
      ; east = Map.fold ~init:(Map.empty (module Int)) ~f:(sider `East) east_col.keys
      }

    let to_scad t =
      let f ~key:_ ~data l = Wall.to_scad data :: l in
      Model.union (Map.fold ~init:(Map.fold ~init:[] ~f t.west) ~f t.east)
  end

  type t =
    { cols : Cols.t
    ; sides : Sides.t
    }

  (* TODO: rough draft. This impl does not allow for different settings between cols
   * and siding. Is that fine? Or should I add more params here, or just make separately? *)
  let make
      ?d1
      ?d2
      ?z_off
      ?thickness
      ?n_steps
      ?north_lookup
      ?south_lookup
      ?west_lookup
      ?east_lookup
      plate
    =
    { cols =
        Cols.make ?d1 ?d2 ?z_off ?thickness ?n_steps ?north_lookup ?south_lookup plate
    ; sides =
        Sides.make ?d1 ?d2 ?z_off ?thickness ?n_steps ?west_lookup ?east_lookup plate
    }

  let to_scad t = Model.union [ Cols.to_scad t.cols; Sides.to_scad t.sides ]
end

module Thumb = struct
  type key =
    { north : Wall.t option
    ; south : Wall.t option
    }

  type sides =
    { west : Wall.t option
    ; east : Wall.t option
    }

  type t =
    { keys : key Map.M(Int).t
    ; sides : sides
    }

  let make
      ?(d1 = 1.)
      ?(d2 = 3.)
      ?(z_off = 0.)
      ?(thickness = 3.5)
      ?(n_steps = `PerZ 4.)
      ?(north_lookup = fun i -> i = 0)
      ?(south_lookup = fun i -> i = 0 || i = 2)
      ?(west = true)
      ?(east = false)
      Plate.{ thumb = { config = { n_keys; _ }; keys; _ }; _ }
    =
    let siding = Wall.poly_siding ~d1 ~d2 ~z_off ~thickness ~n_steps in
    { keys =
        Map.mapi
          ~f:(fun ~key:i ~data ->
            { north = (if north_lookup i then Some (siding `North data) else None)
            ; south = (if south_lookup i then Some (siding `South data) else None)
            } )
          keys
    ; sides =
        { west = (if west then Some (siding `West (Map.find_exn keys 0)) else None)
        ; east =
            (if east then Some (siding `East (Map.find_exn keys (n_keys - 1))) else None)
        }
    }

  let to_scad { keys; sides = { west; east } } =
    let prepend wall l =
      Option.value_map ~default:l ~f:(fun w -> Wall.to_scad w :: l) wall
    in
    Model.union
    @@ Map.fold
         ~init:(prepend west [] |> prepend east)
         ~f:(fun ~key:_ ~data:{ north; south } acc -> prepend north acc |> prepend south)
         keys
end

type t =
  { body : Body.t
  ; thumb : Thumb.t
  }

let to_scad { body; thumb } = Model.union [ Body.to_scad body; Thumb.to_scad thumb ]
