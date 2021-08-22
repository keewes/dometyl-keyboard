open! Base
open! Scad_ml
open! Infix

type 'k t =
  { scad : Model.t
  ; plate : 'k Plate.t
  ; walls : Walls.t
  ; connections : Connect.t
  }

let translate p t =
  { scad = Model.translate p t.scad
  ; plate = Plate.translate p t.plate
  ; walls = Walls.translate p t.walls
  ; connections = Connect.translate p t.connections
  }

let rotate r t =
  { scad = Model.rotate r t.scad
  ; plate = Plate.rotate r t.plate
  ; walls = Walls.rotate r t.walls
  ; connections = Connect.rotate r t.connections
  }

let rotate_about_pt r p t =
  { scad = Model.rotate_about_pt r p t.scad
  ; plate = Plate.rotate_about_pt r p t.plate
  ; walls = Walls.rotate_about_pt r p t.walls
  ; connections = Connect.rotate_about_pt r p t.connections
  }

let make ~plate_welder ~wall_builder ~base_connector plate =
  let walls = wall_builder plate in
  let connections = base_connector walls in
  { scad =
      Model.difference
        (Model.union
           [ Plate.to_scad plate
           ; Walls.to_scad walls
           ; Connect.to_scad connections
           ; plate_welder plate
           ] )
        [ Ports.make walls; Plate.collect_cutouts plate ]
  ; plate
  ; walls
  ; connections
  }

let to_scad ?(show_caps = false) ?(show_cutouts = false) t =
  let caps = if show_caps then Some (Plate.collect_caps t.plate) else None
  and cutouts =
    if show_cutouts
    then Some (Model.color Color.Black (Plate.collect_cutouts t.plate))
    else None
  in
  [ t.scad ] |> Util.prepend_opt caps |> Util.prepend_opt cutouts |> Model.union
