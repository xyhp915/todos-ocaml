open! Core
open UIKit
open Runtime
open Objc

type native = objc_object structure ptr

let retained_objects = ref []
let retained_blocks = ref []

let retain_object object_ = retained_objects := Obj.repr object_ :: !retained_objects
let retain_block block = retained_blocks := Obj.repr block :: !retained_blocks

let nsstring value = new_string value

let nsarray values =
  let array = NSMutableArray.self |> NSMutableArrayClass.arrayWithCapacity (List.length values) in
  List.iter values ~f:(fun value -> NSMutableArray.addObject value array);
  array
;;

let string_of_nsstring value = if is_nil value then "" else NSString._UTF8String value

let date_formatter format =
  let formatter = NSDateFormatter.self |> alloc |> NSDateFormatter.init in
  NSDateFormatter.setDateFormat (nsstring format) formatter;
  formatter
;;

let format_date ~format date =
  let formatter = date_formatter format in
  NSDateFormatter.stringFromDate date formatter |> string_of_nsstring
;;

let parse_date ~format text =
  let formatter = date_formatter format in
  NSDateFormatter.dateFromString (nsstring text) formatter
;;

let control_action f =
  let block =
    Block.make ~args:Objc_type.[ id ] ~return:Objc_type.void (fun _block _sender -> f ())
  in
  retain_block block;
  UIActionClass.actionWithHandler block UIAction.self
;;

let animate_view view ~duration ~options f =
  let animations = Block.make ~args:Objc_type.[] ~return:Objc_type.void (fun _block -> f ()) in
  retain_block animations;
  UIViewClass.transitionWithView
    view
    ~duration
    ~options
    ~animations
    ~completion:null
    UIView.self
;;

module Tab = struct
  let provider controller =
    let block =
      Block.make ~args:Objc_type.[ id ] ~return:Objc_type.id (fun _block _tab -> controller)
    in
    retain_block block;
    block
  ;;

  let item ~title ~icon ~identifier controller =
    let image = UIImage.self |> UIImageClass.systemImageNamed (nsstring icon) in
    let tab =
      msg_send
        ~self:(get_class "UITab" |> alloc)
        ~cmd:(selector "initWithTitle:image:identifier:viewControllerProvider:")
        ~typ:(id @-> id @-> id @-> (ptr void) @-> returning id)
        (nsstring title)
        image
        (nsstring identifier)
        (provider controller)
    in
    retain_object tab;
    tab
  ;;

  let search controller =
    let tab =
      msg_send
        ~self:(get_class "UISearchTab" |> alloc)
        ~cmd:(selector "initWithViewControllerProvider:")
        ~typ:((ptr void) @-> returning id)
        (provider controller)
    in
    msg_send
      ~self:tab
      ~cmd:(selector "setAutomaticallyActivatesSearch:")
      ~typ:(bool @-> returning void)
      true;
    retain_object tab;
    tab
  ;;

  let set_items tab_controller tabs =
    msg_send
      ~self:tab_controller
      ~cmd:(selector "setTabs:animated:")
      ~typ:(id @-> bool @-> returning void)
      (nsarray tabs)
      false
  ;;

  let set_selected tab_controller tab =
    msg_send
      ~self:tab_controller
      ~cmd:(selector "setSelectedTab:")
      ~typ:(id @-> returning void)
      tab
  ;;

  let selected tab_controller =
    msg_send ~self:tab_controller ~cmd:(selector "selectedTab") ~typ:(returning id)
  ;;

  let identifier tab =
    msg_send ~self:tab ~cmd:(selector "identifier") ~typ:(returning id)
    |> string_of_nsstring
  ;;

  let intercept tab_controller ~should_intercept ~on_intercept =
    let last_selected_tab = ref None in
    let class_name = "TodosTabDelegate" ^ Int.to_string (Oo.id (object end)) in
    let _ =
      Class.define
        class_name
        ~superclass:NSObject.self
        ~methods:
          [ (Define.method_spec
               ~cmd:(selector "tabBarController:shouldSelectTab:")
               ~typ:(id @-> id @-> returning bool)
               ~enc:"c32@0:8@16@24"
             @@ fun self _cmd _tab_controller tab ->
             if should_intercept tab
             then (
               let previous_tab =
                 match !last_selected_tab with
                 | Some tab when not (is_nil tab) -> tab
                 | _ -> selected tab_controller
               in
               last_selected_tab := Some previous_tab;
               on_intercept ();
               NSObject.performSelector3
                 (selector "restoreSelectedTab:")
                 ~withObject:tab_controller
                 ~afterDelay:0.
                 self;
               false)
             else true)
          ; (Define.method_spec
               ~cmd:(selector "tabBarController:didSelectTab:previousTab:")
               ~typ:(id @-> id @-> id @-> returning void)
               ~enc:"v40@0:8@16@24@32"
             @@ fun _self _cmd _tab_controller selected_tab _previous_tab ->
             if not (should_intercept selected_tab)
             then last_selected_tab := Some selected_tab)
          ; (Define.method_spec
               ~cmd:(selector "restoreSelectedTab:")
               ~typ:(id @-> returning void)
               ~enc:"v32@0:8@16"
             @@ fun _self _cmd tab_controller ->
             match !last_selected_tab with
             | Some tab when not (is_nil tab) -> set_selected tab_controller tab
             | _ -> ())
          ]
    in
    let delegate_ = Objc.get_class class_name |> alloc |> init in
    retain_object delegate_;
    UITabBarController.setDelegate delegate_ tab_controller
  ;;
end

module Form = struct
  type input =
    | Text
    | Date_picker of
        { mode : int
        ; format : string
        }

  type field =
    { key : string
    ; placeholder : string
    ; text : string
    ; input : input
    }

  let text ~key ~placeholder ~value = { key; placeholder; text = value; input = Text }

  let date_picker ~key ~placeholder ~value ~mode ~format =
    { key; placeholder; text = value; input = Date_picker { mode; format } }
  ;;

  let alert_text_at alert index =
    let fields = UIAlertController.textFields alert in
    if is_nil fields
    then ""
    else (
      let field_count = NSArray.count fields in
      if index >= field_count
      then ""
      else (
        let field = NSArray.objectAtIndex index fields in
        if is_nil field then "" else UITextField.text field |> string_of_nsstring))
  ;;

  let add_field alert field =
    let configure_field =
      Block.make
        ~args:Objc_type.[ id ]
        ~return:Objc_type.void
        (fun _block text_field ->
           UITextField.setPlaceholder (nsstring field.placeholder) text_field;
           UITextField.setText (nsstring field.text) text_field;
           match field.input with
           | Text -> UITextField.setClearButtonMode _UITextFieldViewModeWhileEditing text_field
           | Date_picker { mode; format } ->
             let picker =
               UIDatePicker.self
               |> alloc
               |> UIDatePicker.initWithFrame
                    (CoreGraphics.CGRect.make ~x:0. ~y:0. ~width:0. ~height:216.)
             in
             retain_object picker;
             UIDatePicker.setDatePickerMode mode picker;
             UIDatePicker.setPreferredDatePickerStyle _UIDatePickerStyleWheels picker;
             let parsed = parse_date ~format field.text in
             if not (is_nil parsed) then UIDatePicker.setDate parsed picker;
             UITextField.setInputView picker text_field;
             UITextField.setClearButtonMode _UITextFieldViewModeNever text_field;
             UIControl.addAction
               (control_action (fun () ->
                  UIDatePicker.date picker
                  |> format_date ~format
                  |> nsstring
                  |> fun value -> UITextField.setText value text_field))
               ~forControlEvents:_UIControlEventValueChanged
               picker)
    in
    retain_block configure_field;
    UIAlertController.addTextFieldWithConfigurationHandler configure_field alert
  ;;

  let values alert fields =
    fields
    |> List.mapi ~f:(fun index field -> field.key, alert_text_at alert index)
    |> String.Map.of_alist_exn
  ;;

  let alert_action ~title ~style f =
    let block =
      Block.make ~args:Objc_type.[ id ] ~return:Objc_type.void (fun _block _action -> f ())
    in
    retain_block block;
    UIAlertActionClass.actionWithTitle (nsstring title) ~style ~handler:block UIAlertAction.self
  ;;

  let present controller ~title ~primary_action ~fields ~on_submit =
    let alert =
      UIAlertControllerClass.alertControllerWithTitle
        (nsstring title)
        ~message:nil
        ~preferredStyle:_UIAlertControllerStyleAlert
        UIAlertController.self
    in
    List.iter fields ~f:(add_field alert);
    UIAlertController.addAction
      (alert_action ~title:"Cancel" ~style:_UIAlertActionStyleCancel (fun () -> ()))
      alert;
    UIAlertController.addAction
      (alert_action ~title:primary_action ~style:_UIAlertActionStyleDefault (fun () ->
         on_submit (values alert fields)))
      alert;
    UIViewController.presentViewController alert ~animated:true ~completion:null controller
  ;;
end

module Swipe = struct
  type action =
    { title : string
    ; style : int
    ; color : native
    ; on_select : unit -> unit
    }

  let action { title; style; color; on_select } =
    let block =
      Block.make
        ~args:Objc_type.[ id; id; ptr void ]
        ~return:Objc_type.void
        (fun _block _action _source_view _completion -> on_select ())
    in
    retain_block block;
    let action =
      UIContextualActionClass.contextualActionWithStyle
        style
        ~title:(nsstring title)
        ~handler:block
        UIContextualAction.self
    in
    UIContextualAction.setBackgroundColor color action;
    action
  ;;

  let trailing actions =
    let configuration =
      UISwipeActionsConfigurationClass.configurationWithActions
        (actions |> List.map ~f:action |> nsarray)
        UISwipeActionsConfiguration.self
    in
    UISwipeActionsConfiguration.setPerformsFirstActionWithFullSwipe false configuration;
    configuration
  ;;
end
