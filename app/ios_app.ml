open! Core
open UIKit
open Runtime
open Objc

module Apple = Bonsai_apple
module App = Bonsai_apple_uikit.App
module Presentation = Todos.Todo_presentation
module Store = Todos.Todo_store

let mounted_apps = ref []
let window = ref None
let root_controller = ref None
let table_view = ref None
let table_views = ref []
let search_query = ref ""
let store = ref (Store.demo ())
let todos_cache = ref (Store.all !store)
let retained_objects = ref []

let nsstring value = new_string value

let flexible_size_mask = _UIViewAutoresizingFlexibleWidth lor _UIViewAutoresizingFlexibleHeight

let zero_rect = CoreGraphics.CGRect.make ~x:0. ~y:0. ~width:0. ~height:0.
let table_tag = 1001

let retain_object object_ = retained_objects := Obj.repr object_ :: !retained_objects

let refresh_cache () = todos_cache := Store.all !store

type tab_spec =
  { title : string
  ; icon : string
  ; identifier : string
  }

let today_tab_spec = { title = "Today"; icon = "sun.max"; identifier = "today" }
let upcoming_tab_spec = { title = "Upcoming"; icon = "calendar"; identifier = "upcoming" }
let add_tab_spec = { title = "Add"; icon = "plus"; identifier = "add" }

let make_tab spec controller =
  Native_ui.Tab.item
    ~title:spec.title
    ~icon:spec.icon
    ~identifier:spec.identifier
    controller
;;

let string_of_nsstring value = if is_nil value then "" else NSString._UTF8String value

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

let sections_for ~mode ~query () =
  Presentation.sections_for ~mode ~query !todos_cache
;;

let todo_at ~mode ~query index_path =
  let section_index = NSIndexPath.section index_path in
  let row_index = NSIndexPath.row index_path in
  sections_for ~mode ~query ()
  |> Fn.flip List.nth section_index
  |> Option.bind ~f:(fun (section : Presentation.section) ->
    List.nth section.todos row_index)
;;

let reload_table () = List.iter !table_views ~f:UITableView.reloadData

let reload_table_animated () =
  let animate table =
    Native_ui.animate_view
      table
      ~duration:0.22
      ~options:
        (_UIViewAnimationOptionTransitionCrossDissolve
         lor _UIViewAnimationOptionAllowUserInteraction
         lor _UIViewAnimationOptionBeginFromCurrentState)
      (fun () -> UITableView.reloadData table)
  in
  match !table_views with
  | [] -> ()
  | tables -> List.iter tables ~f:animate
;;

let form_value values key = Map.find values key |> Option.value ~default:""

let save_task ?todo values =
  let title = form_value values "title" in
  let date = form_value values "date" in
  let time = form_value values "time" in
  store
  := (match todo with
      | None -> Store.add !store ~title ~date ~time
      | Some todo -> Store.rename !store ~id:todo.Store.id ~title ~date ~time);
  refresh_cache ();
  reload_table ()
;;

let present_editor ?todo () =
  match !root_controller with
  | None -> ()
  | Some controller ->
    let title, primary_action, initial_title, initial_date, initial_time =
      match todo with
      | None -> "New Task", "Add", "", "Today", ""
      | Some todo -> "Edit Task", "Save", todo.Store.title, todo.Store.date, todo.Store.time
    in
    Native_ui.Form.present
      controller
      ~title
      ~primary_action
      ~fields:
        [ Native_ui.Form.text
            ~key:"title"
            ~placeholder:"Task title"
            ~value:initial_title
        ; Native_ui.Form.date_picker
            ~key:"date"
            ~placeholder:"Date"
            ~value:initial_date
            ~mode:_UIDatePickerModeDate
            ~format:"MMM d"
        ; Native_ui.Form.date_picker
            ~key:"time"
            ~placeholder:"Time"
            ~value:initial_time
            ~mode:_UIDatePickerModeTime
            ~format:"h:mm a"
        ]
      ~on_submit:(save_task ?todo)
;;

let install_tab_delegate tab_controller =
  Native_ui.Tab.intercept
    tab_controller
    ~should_intercept:(fun tab -> String.equal (Native_ui.Tab.identifier tab) "add")
    ~on_intercept:present_editor
;;

let make_checkbox_button todo =
  let button = UIButton.self |> UIButtonClass.buttonWithType _UIButtonTypeSystem in
  UIView.setFrame (CoreGraphics.CGRect.make ~x:8. ~y:0. ~width:48. ~height:58.) button;
  UIView.setAutoresizingMask _UIViewAutoresizingFlexibleRightMargin button;
  let image =
    UIImageClass.systemImageNamed
      (nsstring (if todo.Store.completed then "checkmark.circle.fill" else "circle"))
      UIImage.self
  in
  UIButton.setImage image ~forState:_UIControlStateNormal button;
  UIButton.setTintColor
    (if todo.Store.completed
     then UIColorClass.systemGreenColor UIColor.self
     else UIColorClass.systemGray3Color UIColor.self)
    button;
  let toggle_action =
    Native_ui.control_action (fun () ->
      store := Store.toggle !store ~id:todo.Store.id;
      refresh_cache ();
      reload_table_animated ())
  in
  UIControl.addAction toggle_action ~forControlEvents:_UIControlEventTouchUpInside button;
  button
;;

let make_cell_content todo =
  let content =
    UIListContentConfigurationClass.valueCellConfiguration UIListContentConfiguration.self
  in
  if todo.Store.completed
  then UIListContentConfiguration.setAttributedText (strikethrough todo.Store.title) content
  else UIListContentConfiguration.setText (nsstring todo.Store.title) content;
  UIListContentConfiguration.setSecondaryText
    (nsstring (Presentation.todo_metadata todo))
    content;
  UIListContentConfiguration.setPrefersSideBySideTextAndSecondaryText true content;
  UIListContentConfiguration.setImageToTextPadding 12. content;
  UIListContentConfiguration.setTextToSecondaryTextHorizontalPadding 16. content;
  let image =
    UIImageClass.systemImageNamed
      (nsstring (if todo.Store.completed then "checkmark.circle.fill" else "circle"))
      UIImage.self
  in
  UIListContentConfiguration.setImage image content;
  let image_properties = UIListContentConfiguration.imageProperties content in
  UIListContentImageProperties.setTintColor
    (if todo.Store.completed
     then UIColorClass.systemGreenColor UIColor.self
     else UIColorClass.systemGray3Color UIColor.self)
    image_properties;
  UIListContentImageProperties.setReservedLayoutSize
    (CoreGraphics.CGSize.init ~width:30. ~height:30.)
    image_properties;
  let text_properties = UIListContentConfiguration.textProperties content in
  UIListContentTextProperties.setFont (system_font 16.5) text_properties;
  UIListContentTextProperties.setNumberOfLines 1 text_properties;
  UIListContentTextProperties.setColor
    (if todo.Store.completed
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

let configure_cell cell todo =
  UITableViewCell.setAccessoryType _UITableViewCellAccessoryNone cell;
  UITableViewCell.setSelectionStyle _UITableViewCellSelectionStyleDefault cell;
  let content = UITableViewCell.contentView cell in
  UITableViewCell.setContentConfiguration (make_cell_content todo) cell;
  UIView.addSubview (make_checkbox_button todo) content;
  cell
;;

let make_table_data_source ~mode ~query () =
  let class_name = "TodosTableDataSource" ^ Int.to_string (Oo.id (object end)) in
  let _ =
    Class.define
      class_name
      ~superclass:NSObject.self
      ~methods:
        [ (UITableViewControllerMethods.numberOfSectionsInTableView'
           @@ fun _self _cmd _table ->
           sections_for ~mode ~query:(query ()) () |> List.length |> LLong.of_int)
        ; (UITableViewControllerMethods.tableView'numberOfRowsInSection'
           @@ fun _self _cmd _table section ->
           sections_for ~mode ~query:(query ()) ()
           |> Fn.flip List.nth (LLong.to_int section)
           |> Option.value_map ~default:0 ~f:(fun (section : Presentation.section) ->
             List.length section.todos)
           |> LLong.of_int)
        ; (UITableViewControllerMethods.tableView'titleForHeaderInSection'
           @@ fun _self _cmd _table section ->
           sections_for ~mode ~query:(query ()) ()
           |> Fn.flip List.nth (LLong.to_int section)
           |> Option.value_map ~default:nil ~f:(fun (section : Presentation.section) ->
             let header_title =
               Presentation.header_title
                 ~mode
                 ~section_title:section.title
                 ~todo_count:(List.length section.todos)
             in
             if String.is_empty header_title then nil else nsstring header_title))
        ; (UITableViewControllerMethods.tableView'cellForRowAtIndexPath'
           @@ fun _self _cmd _table index_path ->
           let cell =
             UITableViewCell.self
             |> alloc
             |> UITableViewCell.initWithStyle
                  _UITableViewCellStyleSubtitle
                  ~reuseIdentifier:(nsstring "TodoCell")
           in
           let query = query () in
           match todo_at ~mode ~query index_path with
           | None -> cell
           | Some todo -> configure_cell cell todo)
        ; (UITableViewDelegate.tableView'heightForRowAtIndexPath'
           @@ fun _self _cmd _table _index_path -> 58.)
        ; (UITableViewDelegate.tableView'didSelectRowAtIndexPath'
           @@ fun _self _cmd table index_path ->
           if Option.is_some (todo_at ~mode ~query:(query ()) index_path)
           then UITableView.deselectRowAtIndexPath index_path ~animated:true table)
        ; (UITableViewDelegate.tableView'trailingSwipeActionsConfigurationForRowAtIndexPath'
           @@ fun _self _cmd _table index_path ->
           match todo_at ~mode ~query:(query ()) index_path with
           | None -> nil
           | Some todo ->
             Native_ui.Swipe.trailing
               [ { title = "Delete"
                 ; style = _UIContextualActionStyleDestructive
                 ; color = UIColorClass.systemRedColor UIColor.self
                 ; on_select =
                     (fun () ->
                       store := Store.delete !store ~id:todo.Store.id;
                       refresh_cache ();
                       reload_table ())
                 }
               ; { title = "Edit"
                 ; style = _UIContextualActionStyleNormal
                 ; color = UIColorClass.systemBlueColor UIColor.self
                 ; on_select = (fun () -> present_editor ~todo ())
                 }
               ])
        ]
  in
  Objc.get_class class_name |> alloc |> init
;;

let make_header_view () =
  let header =
    UIView.self
    |> alloc
    |> UIView.initWithFrame (CoreGraphics.CGRect.make ~x:0. ~y:0. ~width:390. ~height:112.)
  in
  UIView.setBackgroundColor (UIColorClass.clearColor UIColor.self) header;
  let title =
    UILabel.self
    |> alloc
    |> UILabel.initWithFrame (CoreGraphics.CGRect.make ~x:20. ~y:30. ~width:320. ~height:34.)
  in
  UILabel.setText (nsstring "Good morning") title;
  UILabel.setFont (bold_system_font 28.) title;
  UILabel.setTextColor (UIColorClass.labelColor UIColor.self) title;
  let subtitle =
    UILabel.self
    |> alloc
    |> UILabel.initWithFrame (CoreGraphics.CGRect.make ~x:20. ~y:66. ~width:320. ~height:24.)
  in
  UILabel.setText (nsstring "Let's get things done.") subtitle;
  UILabel.setFont (system_font 17.) subtitle;
  UILabel.setTextColor (UIColorClass.secondaryLabelColor UIColor.self) subtitle;
  UIView.addSubview title header;
  UIView.addSubview subtitle header;
  header
;;

let install_search_controller controller =
  let search_controller =
    UISearchController.self |> alloc |> UISearchController.initWithSearchResultsController nil
  in
  retain_object search_controller;
  UISearchController.setObscuresBackgroundDuringPresentation false search_controller;
  UISearchController.setHidesNavigationBarDuringPresentation false search_controller;
  UISearchController.setAutomaticallyShowsCancelButton true search_controller;
  let search_bar = UISearchController.searchBar search_controller in
  UISearchBar.setPlaceholder (nsstring "Search") search_bar;
  UISearchBar.setSearchBarStyle _UISearchBarStyleMinimal search_bar;
  let class_name = "TodosNativeSearchDelegate" ^ Int.to_string (Oo.id (object end)) in
  let _ =
    Class.define
      class_name
      ~superclass:NSObject.self
      ~methods:
        [ (UISearchBarDelegate.searchBar'textDidChange'
           @@ fun _self _cmd _search_bar text ->
           search_query := string_of_nsstring text;
           reload_table ())
        ; (UISearchBarDelegate.searchBarCancelButtonClicked'
           @@ fun _self _cmd _search_bar ->
           search_query := "";
           reload_table ())
        ]
  in
  let delegate_ = Objc.get_class class_name |> alloc |> init in
  retain_object delegate_;
  UISearchBar.setDelegate delegate_ search_bar;
  let navigation_item = UIViewController.navigationItem controller in
  UINavigationItem.setSearchController search_controller navigation_item;
  UINavigationItem.setHidesSearchBarWhenScrolling true navigation_item
;;

let layout_table_view self =
  let bounds = UIView.bounds self in
  let size = CoreGraphics.CGRect.size bounds in
  let width = CoreGraphics.CGSize.width size in
  let height = CoreGraphics.CGSize.height size in
  let table = UIView.viewWithTag table_tag self in
  if not (is_nil table)
  then UIView.setFrame (CoreGraphics.CGRect.make ~x:0. ~y:0. ~width ~height) table
;;

let install_table_view ~mode ~query ?(show_header = false) self =
  if is_nil (UIView.viewWithTag table_tag self)
  then (
    UIView.setBackgroundColor (UIColorClass.systemGroupedBackgroundColor UIColor.self) self;
    let table =
      UITableView.self
      |> alloc
      |> UITableView.initWithFrame' zero_rect ~style:_UITableViewStyleInsetGrouped
    in
    table_view := Some table;
    UIView.setTag table_tag table;
    UIView.setAutoresizingMask flexible_size_mask table;
    UITableView.setBackgroundColor (UIColorClass.systemGroupedBackgroundColor UIColor.self) table;
    UITableView.setShowsVerticalScrollIndicator false table;
    UITableView.setRowHeight 58. table;
    UITableView.setEstimatedRowHeight 58. table;
    UITableView.setSectionHeaderTopPadding 8. table;
    UITableView.setContentInset
      (UIEdgeInsets.init ~top:0. ~left:0. ~bottom:118. ~right:0.)
      table;
    if show_header then UITableView.setTableHeaderView (make_header_view ()) table;
    let data_source = make_table_data_source ~mode ~query () in
    retain_object data_source;
    UITableView.setDataSource data_source table;
    UITableView.setDelegate data_source table;
    UIView.addSubview table self;
    table_views := table :: !table_views;
    layout_table_view self);
  self
;;

type table_screen =
  { class_name : string
  ; mode : Presentation.mode
  ; query : unit -> string
  ; show_header : bool
  }

let dashboard_screen =
  { class_name = "TodosDashboardView"
  ; mode = Presentation.Dashboard
  ; query = (fun () -> "")
  ; show_header = true
  }

let upcoming_screen =
  { class_name = "TodosUpcomingView"
  ; mode = Presentation.Upcoming
  ; query = (fun () -> "")
  ; show_header = false
  }

let search_screen =
  { class_name = "TodosSearchView"
  ; mode = Presentation.Search
  ; query = (fun () -> !search_query)
  ; show_header = false
  }

let register_table_screen screen =
  let _ =
    Class.define
      screen.class_name
      ~superclass:UIView.self
      ~methods:
        [ (UIViewMethods.didMoveToSuperview
           @@ fun self _cmd ->
           ignore
             (install_table_view
                ~mode:screen.mode
                ~query:screen.query
                ~show_header:screen.show_header
                self))
        ; (UIViewMethods.layoutSubviews @@ fun self _cmd -> layout_table_view self)
        ]
  in
  ()
;;

let register_views () =
  [ dashboard_screen; upcoming_screen; search_screen ]
  |> List.iter ~f:register_table_screen
;;

let component _graph = Bonsai.return (Apple.custom_view ~kind:"TodosDashboardView" ())

let install_tab_item spec controller =
  let title = nsstring spec.title in
  let image = UIImage.self |> UIImageClass.systemImageNamed (nsstring spec.icon) in
  let item =
    UITabBarItem.self |> alloc |> UITabBarItem.initWithTitle title ~image ~selectedImage:nil
  in
  UIViewController.setTitle title controller;
  UIViewController.setTabBarItem item controller
;;

let make_table_controller ~tab ~class_name ~screen_bounds =
  let controller = UIViewController.self |> alloc |> init in
  let view = Objc.get_class class_name |> alloc |> UIView.initWithFrame screen_bounds in
  UIView.setAutoresizingMask flexible_size_mask view;
  UIViewController.setView view controller;
  UIViewController.setTitle (nsstring tab.title) controller;
  let navigation =
    UINavigationController.self
    |> alloc
    |> UINavigationController.initWithRootViewController controller
  in
  install_tab_item tab navigation;
  controller, navigation
;;

let install_root_view ~time_source app_delegate _cmd _application _launch_options =
  register_views ();
  let screen_bounds = UIScreen.self |> UIScreenClass.mainScreen |> UIScreen.bounds in
  let background_color = UIColor.self |> UIColorClass.systemGroupedBackgroundColor in
  let win = UIWindow.self |> alloc |> UIWindow.initWithFrame screen_bounds in
  UIView.setBackgroundColor background_color win;
  table_views := [];
  let app = App.create ~time_source component in
  App.flush_and_render app;
  mounted_apps := [ app ];
  let tab_controller = UITabBarController.self |> alloc |> init in
  (match App.view app with
   | None -> ()
   | Some root ->
     let root_view = Bonsai_apple_uikit.native root in
     let controller = Bonsai_apple_uikit.controller root in
     UIView.setAutoresizingMask flexible_size_mask root_view;
     UIView.setBackgroundColor background_color root_view;
     let upcoming_controller, _upcoming_navigation =
       make_table_controller
         ~tab:upcoming_tab_spec
         ~class_name:upcoming_screen.class_name
         ~screen_bounds
     in
     let search_controller, search_navigation =
       make_table_controller
         ~tab:{ title = "Search"; icon = "magnifyingglass"; identifier = "search" }
         ~class_name:search_screen.class_name
         ~screen_bounds
     in
     install_search_controller search_controller;
     let today_tab = make_tab today_tab_spec controller in
     let upcoming_tab = make_tab upcoming_tab_spec upcoming_controller in
     let add_controller = UIViewController.self |> alloc |> init in
     let add_tab = make_tab add_tab_spec add_controller in
     let search_tab = Native_ui.Tab.search search_navigation in
     Native_ui.Tab.set_items tab_controller [ today_tab; upcoming_tab; add_tab; search_tab ];
     Native_ui.Tab.set_selected tab_controller today_tab;
     root_controller := Some tab_controller;
     install_tab_delegate tab_controller;
     UIWindow.setRootViewController tab_controller win);
  UIWindow.makeKeyAndVisible win;
  window := Some win;
  ignore app_delegate;
  true
;;

let main ~time_source =
  let _ =
    Class.define
      "TodosAppDelegate"
      ~superclass:UIResponder.self
      ~methods:
        [ (UIApplicationDelegate.application'didFinishLaunchingWithOptions'
           @@ install_root_view ~time_source)
        ]
  in
  _UIApplicationMain
    0
    (Objc.from_voidp Objc.string Objc.null)
    nil
    (new_string "TodosAppDelegate")
  |> exit
;;

let () = main ~time_source:(Bonsai.Time_source.create ~start:Time_ns.epoch)
