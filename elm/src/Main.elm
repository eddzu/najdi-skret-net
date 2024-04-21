port module Main exposing (main)

import Acceleration
import Angle
import Axis3d exposing (Axis3d)
import Block3d exposing (Block3d)
import Browser
import Browser.Dom
import Browser.Events
import Camera3d exposing (Camera3d)
import Color
import Direction3d
import Duration exposing (seconds)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Json.Decode exposing (Decoder)
import Length exposing (Meters, millimeters)
import Mass exposing (kilograms)
import Physics.Body as Body exposing (Body)
import Physics.Constraint as Constraint
import Physics.Coordinates exposing (BodyCoordinates, WorldCoordinates)
import Physics.Shape
import Physics.World as World exposing (RaycastResult, World)
import Pixels exposing (Pixels, pixels)
import Plane3d
import Point2d
import Point3d
import Quantity exposing (Quantity)
import Rectangle2d
import Scene3d
import Scene3d.Material exposing (Texture)
import Scene3d.Mesh exposing (Shadow, Textured)
import Sphere3d
import Task
import Viewpoint3d
import WebGL.Texture
import Http
import Color exposing (Color)
import Obj.Decode exposing (Decoder, ObjCoordinates)
import Frame3d exposing (Frame3d)
import Physics.Coordinates exposing (BodyCoordinates)

bodyFrame : Frame3d Meters BodyCoordinates { defines : ObjCoordinates }
bodyFrame =
    Frame3d.atOrigin

type Id
    = Mouse
    | Floor
    | Poop
    | Toilet
    | GamePoop


type State
    = BeforeThrow
    | Throwing Int
    | AfterThrow

type alias Model =
    { world : World Id
    , width : Quantity Float Pixels
    , height : Quantity Float Pixels
    , maybeRaycastResult : Maybe (RaycastResult Id)
    , game: State
    , stopped: Bool
    , poopModel : Maybe (Body Meshy)
    }


port stop : (Bool -> msg) -> Sub msg

type Msg
    = AnimationFrame
    | Resize Int Int
    | MouseDown (Axis3d Meters WorldCoordinates)
    | MouseMove (Axis3d Meters WorldCoordinates)
    | MouseUp
    | Stop Bool
    | LoadedPoop (Result Http.Error (Body Meshy))


type alias Meshy =  (Scene3d.Mesh.Mesh BodyCoordinates { normals : () }
                         , Shadow BodyCoordinates)


meshWithShadow : Decoder Meshy
meshWithShadow =
    Obj.Decode.map
        (\fcs ->
            let
                mesh =
                    Scene3d.Mesh.indexedFaces fcs
                        |> Scene3d.Mesh.cullBackFaces
            in
            (mesh, (Scene3d.Mesh.shadow mesh))
        )
        (Obj.Decode.facesIn bodyFrame)

meshes : Body.Behavior -> Decoder (Body Meshy)
meshes b =
    Obj.Decode.map2
        (\convex mesh ->
            Body.compound
                [ Physics.Shape.unsafeConvex convex ]
                mesh
                |> Body.withBehavior b
        )
        -- (Obj.Decode.object "convex" (Obj.Decode.trianglesIn bodyFrame))
        (Obj.Decode.object "mesh" meshWithShadow)



main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = \msg model -> ( update msg model, Cmd.none )
        , subscriptions = subscriptions
        , view = view
        }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { world = initialWorld
      , width = pixels 0
      , height = pixels 0
      , maybeRaycastResult = Nothing
      , game = BeforeThrow
      , stopped = False
      , poopModel = Nothing
      }
    , Cmd.batch
        [ Http.get
              { url = "poop.obj.txt"
              , expect = Obj.Decode.expectObj LoadedPoop Length.meters <| meshes Body.static
              }
        , Task.perform
        (\{ viewport } ->
            Resize (round viewport.width) (round viewport.height)
        )
        Browser.Dom.getViewport
        ]
    )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Browser.Events.onResize Resize
        , Browser.Events.onAnimationFrame (\_ -> AnimationFrame)
        , stop Stop
        ]


initialWorld : World Id
initialWorld =
    World.empty
        |> World.withGravity (Acceleration.gees 1) Direction3d.negativeZ
        |> World.add skret
        |> World.add poop
        |> World.add (Body.plane Floor)


poopBlocks : List (Block3d Meters BodyCoordinates)
poopBlocks =
    [ Block3d.from
        (Point3d.millimeters -50 -50 -50)
        (Point3d.millimeters 50 50 50)
    ]


-- poopPlaceholder :  -> Body Id
-- poopPlaceholder =
--     Body.compound (List.map Physics.Shape.block poopBlocks) Poop
--         |> Body.withBehavior (Body.dynamic (kilograms 1))
skret: Body Id
skret =
    Body.compound (List.map Physics.Shape.block skretModel) Toilet
        |> Body.withBehavior Body.static

skretModel : List (Block3d Meters BodyCoordinates)
skretModel =
    [Block3d.from
         (Point3d.millimeters -50 -50 -50)
         (Point3d.millimeters 50 50 50)
    ]

poop: Body Id
poop =
    Body.sphere (Sphere3d.atPoint (Point3d.meters 1 1 1) (Length.millimeters 100)) Poop
        |> Body.withBehavior Body.static



camera : Camera3d Meters WorldCoordinates
camera =
    Camera3d.perspective
        { viewpoint =
            Viewpoint3d.lookAt
                { eyePoint = Point3d.meters 3 4 2
                , focalPoint = Point3d.meters -0.5 -0.5 0
                , upDirection = Direction3d.positiveZ
                }
        , verticalFieldOfView = Angle.degrees 24
        }


view : Model -> Html Msg
view { world, width, height, stopped, poopModel} =
    case (stopped, poopModel) of
        (True, _) ->
            Html.div [] []
        (_, Nothing) ->
            Html.div [] [Html.text "Loadin..."]
        (False, Just m) ->
            Html.div
                [ Html.Attributes.style "position" "fixed"
                , Html.Attributes.style "left" "0"
                , Html.Attributes.style "top" "10vh"
                , Html.Events.on "mousedown" (decodeMouseRay camera width height MouseDown)
                , Html.Events.on "mousemove" (decodeMouseRay camera width height MouseMove)
                , Html.Events.onMouseUp MouseUp
                ]
                [ Scene3d.sunny
                    { upDirection = Direction3d.z
                    , sunlightDirection = Direction3d.xyZ (Angle.degrees 135) (Angle.degrees -60)
                    , shadows = True
                    , camera = camera
                    , dimensions =
                        ( Pixels.int (round (Pixels.toFloat width))
                        , Pixels.int (round (Pixels.toFloat height))
                        )
                    , background = Scene3d.transparentBackground
                    , clipDepth = Length.meters 0.1
                    , entities = List.map (bodyToEntity m) (World.bodies world)
                    }
                ]


bodyToEntity : (Body Meshy) -> (Body Id) ->  Scene3d.Entity WorldCoordinates
bodyToEntity m body =
    let
        frame =
            Body.frame body

        id =
            Body.data body
    in
    Scene3d.placeIn frame <|
        case id of
            Mouse ->
                Scene3d.sphere (Scene3d.Material.matte Color.white)
                    (Sphere3d.atOrigin (millimeters 20))

            Poop ->
                poopBlocks
                    |> List.map
                        (Scene3d.blockWithShadow
                            (Scene3d.Material.nonmetal
                                { baseColor = Color.white
                                , roughness = 0.25
                                }
                            )
                        )
                    |> Scene3d.group

            Floor ->
                Scene3d.quad (Scene3d.Material.matte Color.darkCharcoal)
                    (Point3d.meters -15 -15 0)
                    (Point3d.meters -15 15 0)
                    (Point3d.meters 15 15 0)
                    (Point3d.meters 15 -15 0)
            Toilet ->
                Scene3d.sphereWithShadow
                    (Scene3d.Material.nonmetal
                         {baseColor = Color.blue
                         , roughness = 0.1
                         }
                    ) (Sphere3d.atOrigin (millimeters 20))
            GamePoop ->
                poopBlocks
                    |> List.map
                        (Scene3d.blockWithShadow
                            (Scene3d.Material.nonmetal
                                { baseColor = Color.white
                                , roughness = 0.25
                                }
                            )
                        )
                    |> Scene3d.group



update : Msg -> Model -> Model
update msg model =
        case msg of
            AnimationFrame ->
                { model | world = World.simulate (seconds (1 / 60)) model.world }

            Resize width height ->
                { model
                    | width = Pixels.float (toFloat width)
                    , height = Pixels.float (toFloat height)
                }

            MouseDown mouseRay ->
                case World.raycast mouseRay model.world of
                    Just raycastResult ->
                        case Body.data raycastResult.body of
                            Poop ->
                                let
                                    worldPoint =
                                        Point3d.placeIn
                                            (Body.frame raycastResult.body)
                                            raycastResult.point

                                    mouse =
                                        Body.compound [] Mouse
                                            |> Body.moveTo worldPoint
                                in
                                { model
                                    | maybeRaycastResult = Just raycastResult
                                    , world =
                                        model.world
                                            |> World.add mouse
                                            |> World.constrain
                                                (\b1 b2 ->
                                                    case ( Body.data b1, Body.data b2 ) of
                                                        ( Mouse, Poop ) ->
                                                            [ Constraint.pointToPoint
                                                                Point3d.origin
                                                                raycastResult.point
                                                            ]

                                                        _ ->
                                                            []
                                                )
                                }

                            _ ->
                                model

                    Nothing ->
                        model

            MouseMove mouseRay ->
                case model.maybeRaycastResult of
                    Just raycastResult ->
                        let
                            worldPoint =
                                Point3d.placeIn
                                    (Body.frame raycastResult.body)
                                    raycastResult.point

                            plane =
                                Plane3d.through
                                    worldPoint
                                    (Viewpoint3d.viewDirection (Camera3d.viewpoint camera))
                        in
                        { model
                            | world =
                                World.update
                                    (\body ->
                                        if Body.data body == Mouse then
                                            case Axis3d.intersectionWithPlane plane mouseRay of
                                                Just intersection ->
                                                    Body.moveTo intersection body

                                                Nothing ->
                                                    body

                                        else
                                            body
                                    )
                                    model.world
                        }

                    Nothing ->
                        model

            MouseUp ->
                { model
                    | maybeRaycastResult = Nothing
                    , world =
                        World.keepIf
                            (\body -> Body.data body /= Mouse)
                            model.world
                }
            Stop s ->
                {model | stopped = s}
            LoadedPoop a ->
                {model | poopModel = Debug.log "b" a
                        |> Result.toMaybe}
            -- LoadedTexture rez ->
            --     {model
            --      | material =
            --         rez
            --             |> Result.map Scene3d.Material.texturedMatte
            --             |> Result.toMaybe
            --     }


decodeMouseRay :
    Camera3d Meters WorldCoordinates
    -> Quantity Float Pixels
    -> Quantity Float Pixels
    -> (Axis3d Meters WorldCoordinates -> msg)
    -> Json.Decode.Decoder msg
decodeMouseRay camera3d width height rayToMsg =
    Json.Decode.map2
        (\x y  ->
             -- let
             --    c = Debug.toString p |> Debug.log 0
             -- in
            rayToMsg
                (Camera3d.ray
                    camera3d
                    (Rectangle2d.with
                        { x1 = pixels 0
                        , y1 = height
                        , x2 = width
                        , y2 = pixels 0
                        }
                    )
                    (Point2d.pixels x y)
                )
        )
        (Json.Decode.field "offsetX" Json.Decode.float)
        (Json.Decode.field "offsetY" Json.Decode.float)
