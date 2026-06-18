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

module Objc_method = struct
  let object_method_encoding ~return_code ~object_arguments =
    let frame_size = 16 + (object_arguments * 8) in
    let arguments =
      List.init object_arguments ~f:(fun index ->
        "@" ^ Int.to_string (16 + (index * 8)))
    in
    return_code ^ Int.to_string frame_size ^ String.concat ("@0" :: ":8" :: arguments)
  ;;

  let object2_returns_bool ~name f =
    Define.method_spec
      ~cmd:(selector name)
      ~typ:(id @-> id @-> returning bool)
      ~enc:(object_method_encoding ~return_code:"c" ~object_arguments:2)
      f
  ;;

  let object3_returns_void ~name f =
    Define.method_spec
      ~cmd:(selector name)
      ~typ:(id @-> id @-> id @-> returning void)
      ~enc:(object_method_encoding ~return_code:"v" ~object_arguments:3)
      f
  ;;

  let object1_returns_void ~name f =
    Define.method_spec
      ~cmd:(selector name)
      ~typ:(id @-> returning void)
      ~enc:(object_method_encoding ~return_code:"v" ~object_arguments:1)
      f
  ;;
end

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
          [ (Objc_method.object2_returns_bool
               ~name:"tabBarController:shouldSelectTab:"
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
          ; (Objc_method.object3_returns_void
               ~name:"tabBarController:didSelectTab:previousTab:"
             @@ fun _self _cmd _tab_controller selected_tab _previous_tab ->
             if not (should_intercept selected_tab)
             then last_selected_tab := Some selected_tab)
          ; (Objc_method.object1_returns_void
               ~name:"restoreSelectedTab:"
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

module Table = struct
  type callbacks =
    { number_of_sections : unit -> int
    ; number_of_rows : section:int -> int
    ; title_for_header : section:int -> string option
    ; cell_for_row : table:native -> index_path:native -> native
    ; height_for_row : index_path:native -> float
    ; did_select : table:native -> index_path:native -> unit
    ; trailing_swipe_actions : table:native -> index_path:native -> native
    }

  let data_source callbacks =
    let class_name = "TodosTableDataSource" ^ Int.to_string (Oo.id (object end)) in
    let _ =
      Class.define
        class_name
        ~superclass:NSObject.self
        ~methods:
          [ (UITableViewControllerMethods.numberOfSectionsInTableView'
             @@ fun _self _cmd _table ->
             callbacks.number_of_sections () |> LLong.of_int)
          ; (UITableViewControllerMethods.tableView'numberOfRowsInSection'
             @@ fun _self _cmd _table section ->
             callbacks.number_of_rows ~section:(LLong.to_int section) |> LLong.of_int)
          ; (UITableViewControllerMethods.tableView'titleForHeaderInSection'
             @@ fun _self _cmd _table section ->
             match callbacks.title_for_header ~section:(LLong.to_int section) with
             | None -> nil
             | Some title -> nsstring title)
          ; (UITableViewControllerMethods.tableView'cellForRowAtIndexPath'
             @@ fun _self _cmd table index_path ->
             callbacks.cell_for_row ~table ~index_path)
          ; (UITableViewDelegate.tableView'heightForRowAtIndexPath'
             @@ fun _self _cmd _table index_path ->
             callbacks.height_for_row ~index_path)
          ; (UITableViewDelegate.tableView'didSelectRowAtIndexPath'
             @@ fun _self _cmd table index_path ->
             callbacks.did_select ~table ~index_path)
          ; (UITableViewDelegate.tableView'trailingSwipeActionsConfigurationForRowAtIndexPath'
             @@ fun _self _cmd table index_path ->
             callbacks.trailing_swipe_actions ~table ~index_path)
          ]
    in
    Objc.get_class class_name |> alloc |> init
  ;;
end

module Search = struct
  let install controller ~placeholder ~on_change ~on_cancel =
    let search_controller =
      UISearchController.self |> alloc |> UISearchController.initWithSearchResultsController nil
    in
    retain_object search_controller;
    UISearchController.setObscuresBackgroundDuringPresentation false search_controller;
    UISearchController.setHidesNavigationBarDuringPresentation false search_controller;
    UISearchController.setAutomaticallyShowsCancelButton true search_controller;
    let search_bar = UISearchController.searchBar search_controller in
    UISearchBar.setPlaceholder (nsstring placeholder) search_bar;
    UISearchBar.setSearchBarStyle _UISearchBarStyleMinimal search_bar;
    let class_name = "TodosNativeSearchDelegate" ^ Int.to_string (Oo.id (object end)) in
    let _ =
      Class.define
        class_name
        ~superclass:NSObject.self
        ~methods:
          [ (UISearchBarDelegate.searchBar'textDidChange'
             @@ fun _self _cmd _search_bar text -> on_change (string_of_nsstring text))
          ; (UISearchBarDelegate.searchBarCancelButtonClicked'
             @@ fun _self _cmd _search_bar -> on_cancel ())
          ]
    in
    let delegate_ = Objc.get_class class_name |> alloc |> init in
    retain_object delegate_;
    UISearchBar.setDelegate delegate_ search_bar;
    let navigation_item = UIViewController.navigationItem controller in
    UINavigationItem.setSearchController search_controller navigation_item;
    UINavigationItem.setHidesSearchBarWhenScrolling true navigation_item
  ;;
end

module View = struct
  let has_tag view ~tag = not (is_nil (UIView.viewWithTag tag view))

  let fill_tagged_subview view ~tag =
    let child = UIView.viewWithTag tag view in
    if not (is_nil child)
    then (
      let bounds = UIView.bounds view in
      let size = CoreGraphics.CGRect.size bounds in
      let width = CoreGraphics.CGSize.width size in
      let height = CoreGraphics.CGSize.height size in
      UIView.setFrame (CoreGraphics.CGRect.make ~x:0. ~y:0. ~width ~height) child)
  ;;

  let register ~class_name ~did_move_to_superview ~layout_subviews =
    let _ =
      Class.define
        class_name
        ~superclass:UIView.self
        ~methods:
          [ (UIViewMethods.didMoveToSuperview
             @@ fun self _cmd -> did_move_to_superview self)
          ; (UIViewMethods.layoutSubviews @@ fun self _cmd -> layout_subviews self)
          ]
    in
    ()
  ;;
end

module Controller = struct
  let flexible_size_mask = _UIViewAutoresizingFlexibleWidth lor _UIViewAutoresizingFlexibleHeight

  let install_tab_item ~title ~icon controller =
    let title = nsstring title in
    let image = UIImage.self |> UIImageClass.systemImageNamed (nsstring icon) in
    let item =
      UITabBarItem.self |> alloc |> UITabBarItem.initWithTitle title ~image ~selectedImage:nil
    in
    UIViewController.setTitle title controller;
    UIViewController.setTabBarItem item controller
  ;;

  let view_class_screen ~title ~icon ~class_name ~frame =
    let controller = UIViewController.self |> alloc |> init in
    let view = Objc.get_class class_name |> alloc |> UIView.initWithFrame frame in
    UIView.setAutoresizingMask flexible_size_mask view;
    UIViewController.setView view controller;
    UIViewController.setTitle (nsstring title) controller;
    let navigation =
      UINavigationController.self
      |> alloc
      |> UINavigationController.initWithRootViewController controller
    in
    install_tab_item ~title ~icon navigation;
    controller, navigation
  ;;
end

module Application = struct
  let run ~delegate_class ~did_finish_launching =
    let _ =
      Class.define
        delegate_class
        ~superclass:UIResponder.self
        ~methods:
          [ (UIApplicationDelegate.application'didFinishLaunchingWithOptions'
             @@ fun app_delegate _cmd application launch_options ->
             did_finish_launching app_delegate application launch_options)
          ]
    in
    _UIApplicationMain
      0
      (Objc.from_voidp Objc.string Objc.null)
      nil
      (new_string delegate_class)
    |> exit
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

module Todo_list = struct
  type row =
    { id : int
    ; title : string
    ; secondary : string
    ; completed : bool
    ; on_toggle : unit -> unit
    ; on_edit : unit -> unit
    ; on_delete : unit -> unit
    }

  type section =
    { title : string option
    ; rows : row list
    }

  type header =
    { title : string
    ; subtitle : string
    }

  let reload table = UITableView.reloadData table

  let reload_animated table =
    animate_view
      table
      ~duration:0.22
      ~options:
        (_UIViewAnimationOptionTransitionCrossDissolve
         lor _UIViewAnimationOptionAllowUserInteraction
         lor _UIViewAnimationOptionBeginFromCurrentState)
      (fun () -> reload table)
  ;;

  let system_font size =
    msg_send
      ~self:(get_class "UIFont")
      ~cmd:(selector "systemFontOfSize:")
      ~typ:(double @-> returning id)
      size
  ;;

  let bold_system_font size =
    msg_send
      ~self:(get_class "UIFont")
      ~cmd:(selector "boldSystemFontOfSize:")
      ~typ:(double @-> returning id)
      size
  ;;

  let attributed_string value =
    msg_send
      ~self:(NSMutableAttributedString.self |> alloc)
      ~cmd:(selector "initWithString:")
      ~typ:(id @-> returning id)
      (nsstring value)
  ;;

  let strikethrough value =
    let attributed = attributed_string value in
    let range =
      NSRange.init ~location:(ULLong.of_int 0) ~length:(ULLong.of_int (String.length value)) ()
    in
    NSMutableAttributedString.addAttribute
      _NSStrikethroughStyleAttributeName
      ~value:(NSNumberClass.numberWithInt 1 NSNumber.self)
      ~range
      attributed;
    NSMutableAttributedString.addAttribute
      _NSStrikethroughColorAttributeName
      ~value:(UIColorClass.secondaryLabelColor UIColor.self)
      ~range
      attributed;
    attributed
  ;;

  let checkbox_image completed =
    UIImageClass.systemImageNamed
      (nsstring (if completed then "checkmark.circle.fill" else "circle"))
      UIImage.self
  ;;

  let checkbox_tint completed =
    if completed
    then UIColorClass.systemGreenColor UIColor.self
    else UIColorClass.systemGray3Color UIColor.self
  ;;

  let make_checkbox_button row =
    let button = UIButton.self |> UIButtonClass.buttonWithType _UIButtonTypeSystem in
    UIView.setFrame (CoreGraphics.CGRect.make ~x:8. ~y:0. ~width:48. ~height:58.) button;
    UIView.setAutoresizingMask _UIViewAutoresizingFlexibleRightMargin button;
    UIButton.setImage (checkbox_image row.completed) ~forState:_UIControlStateNormal button;
    UIButton.setTintColor (checkbox_tint row.completed) button;
    UIControl.addAction
      (control_action row.on_toggle)
      ~forControlEvents:_UIControlEventTouchUpInside
      button;
    button
  ;;

  let make_cell_content row =
    let content =
      UIListContentConfigurationClass.valueCellConfiguration UIListContentConfiguration.self
    in
    if row.completed
    then UIListContentConfiguration.setAttributedText (strikethrough row.title) content
    else UIListContentConfiguration.setText (nsstring row.title) content;
    UIListContentConfiguration.setSecondaryText (nsstring row.secondary) content;
    UIListContentConfiguration.setPrefersSideBySideTextAndSecondaryText true content;
    UIListContentConfiguration.setImageToTextPadding 12. content;
    UIListContentConfiguration.setTextToSecondaryTextHorizontalPadding 16. content;
    UIListContentConfiguration.setImage (checkbox_image row.completed) content;
    let image_properties = UIListContentConfiguration.imageProperties content in
    UIListContentImageProperties.setTintColor (checkbox_tint row.completed) image_properties;
    UIListContentImageProperties.setReservedLayoutSize
      (CoreGraphics.CGSize.init ~width:30. ~height:30.)
      image_properties;
    let text_properties = UIListContentConfiguration.textProperties content in
    UIListContentTextProperties.setFont (system_font 16.5) text_properties;
    UIListContentTextProperties.setNumberOfLines 1 text_properties;
    UIListContentTextProperties.setColor
      (if row.completed
       then UIColorClass.secondaryLabelColor UIColor.self
       else UIColorClass.labelColor UIColor.self)
      text_properties;
    let secondary_properties =
      UIListContentConfiguration.secondaryTextProperties content
    in
    UIListContentTextProperties.setFont (system_font 13.) secondary_properties;
    UIListContentTextProperties.setAlignment _UITextAlignmentRight secondary_properties;
    UIListContentTextProperties.setColor
      (UIColorClass.secondaryLabelColor UIColor.self)
      secondary_properties;
    content
  ;;

  let configure_cell row =
    let cell =
      UITableViewCell.self
      |> alloc
      |> UITableViewCell.initWithStyle
           _UITableViewCellStyleSubtitle
           ~reuseIdentifier:(nsstring "TodoCell")
    in
    UITableViewCell.setAccessoryType _UITableViewCellAccessoryNone cell;
    UITableViewCell.setSelectionStyle _UITableViewCellSelectionStyleDefault cell;
    UITableViewCell.setContentConfiguration (make_cell_content row) cell;
    UITableViewCell.contentView cell |> UIView.addSubview (make_checkbox_button row);
    cell
  ;;

  let row_at sections index_path =
    let section_index = NSIndexPath.section index_path in
    let row_index = NSIndexPath.row index_path in
    sections
    |> Fn.flip List.nth section_index
    |> Option.bind ~f:(fun section -> List.nth section.rows row_index)
  ;;

  let make_data_source ~sections =
    Table.data_source
      { number_of_sections = (fun () -> List.length (sections ()))
      ; number_of_rows =
          (fun ~section ->
             sections ()
             |> Fn.flip List.nth section
             |> Option.value_map ~default:0 ~f:(fun section -> List.length section.rows))
      ; title_for_header =
          (fun ~section ->
             sections ()
             |> Fn.flip List.nth section
             |> Option.bind ~f:(fun section -> section.title))
      ; cell_for_row =
          (fun ~table:_ ~index_path ->
             match row_at (sections ()) index_path with
             | None ->
               UITableViewCell.self
               |> alloc
               |> UITableViewCell.initWithStyle
                    _UITableViewCellStyleSubtitle
                    ~reuseIdentifier:(nsstring "TodoCell")
             | Some row -> configure_cell row)
      ; height_for_row = (fun ~index_path:_ -> 58.)
      ; did_select =
          (fun ~table ~index_path ->
             if Option.is_some (row_at (sections ()) index_path)
             then UITableView.deselectRowAtIndexPath index_path ~animated:true table)
      ; trailing_swipe_actions =
          (fun ~table:_ ~index_path ->
             match row_at (sections ()) index_path with
             | None -> nil
             | Some row ->
               Swipe.trailing
                 [ { title = "Delete"
                   ; style = _UIContextualActionStyleDestructive
                   ; color = UIColorClass.systemRedColor UIColor.self
                   ; on_select = row.on_delete
                   }
                 ; { title = "Edit"
                   ; style = _UIContextualActionStyleNormal
                   ; color = UIColorClass.systemBlueColor UIColor.self
                   ; on_select = row.on_edit
                   }
                 ])
      }
  ;;

  let header_view header =
    let view =
      UIView.self
      |> alloc
      |> UIView.initWithFrame (CoreGraphics.CGRect.make ~x:0. ~y:0. ~width:390. ~height:112.)
    in
    UIView.setBackgroundColor (UIColorClass.clearColor UIColor.self) view;
    let title =
      UILabel.self
      |> alloc
      |> UILabel.initWithFrame (CoreGraphics.CGRect.make ~x:20. ~y:30. ~width:320. ~height:34.)
    in
    UILabel.setText (nsstring header.title) title;
    UILabel.setFont (bold_system_font 28.) title;
    UILabel.setTextColor (UIColorClass.labelColor UIColor.self) title;
    let subtitle =
      UILabel.self
      |> alloc
      |> UILabel.initWithFrame (CoreGraphics.CGRect.make ~x:20. ~y:66. ~width:320. ~height:24.)
    in
    UILabel.setText (nsstring header.subtitle) subtitle;
    UILabel.setFont (system_font 17.) subtitle;
    UILabel.setTextColor (UIColorClass.secondaryLabelColor UIColor.self) subtitle;
    UIView.addSubview title view;
    UIView.addSubview subtitle view;
    view
  ;;

  let install host ~tag ~header ~sections =
    UIView.setBackgroundColor (UIColorClass.systemGroupedBackgroundColor UIColor.self) host;
    let table =
      UITableView.self
      |> alloc
      |> UITableView.initWithFrame'
           (CoreGraphics.CGRect.make ~x:0. ~y:0. ~width:0. ~height:0.)
           ~style:_UITableViewStyleInsetGrouped
    in
    UIView.setTag tag table;
    UIView.setAutoresizingMask
      (_UIViewAutoresizingFlexibleWidth lor _UIViewAutoresizingFlexibleHeight)
      table;
    UITableView.setBackgroundColor (UIColorClass.systemGroupedBackgroundColor UIColor.self) table;
    UITableView.setShowsVerticalScrollIndicator false table;
    UITableView.setRowHeight 58. table;
    UITableView.setEstimatedRowHeight 58. table;
    UITableView.setSectionHeaderTopPadding 8. table;
    UITableView.setContentInset
      (UIEdgeInsets.init ~top:0. ~left:0. ~bottom:118. ~right:0.)
      table;
    Option.iter header ~f:(fun header -> UITableView.setTableHeaderView (header_view header) table);
    let data_source = make_data_source ~sections in
    retain_object data_source;
    UITableView.setDataSource data_source table;
    UITableView.setDelegate data_source table;
    UIView.addSubview table host;
    View.fill_tagged_subview host ~tag;
    table
  ;;
end
