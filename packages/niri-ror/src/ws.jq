#!/usr/bin/env -S jq -f

# Import filters and operators
include "filters";
include "operators";

# Helper to stop the complaining 
def default_arg($arg_name; $default):
  $ARGS.named[$arg_name] // $default;

def effective_operation($requested; $app_id_filter; $title_filter):
  if $requested != "" then
    $requested
  elif ($app_id_filter != "" and $title_filter != "") then
    "intersection"
  else
    ""
  end;


def apply_filters($app_id_filter; $title_filter; $app_id_regex; $title_regex; $exclude_focused; $operation; $printdebug; $list_only):
  . as $input |
  (effective_operation($operation; ($app_id_filter + $app_id_regex); ($title_filter + $title_regex))) as $raw_op |
  ($raw_op | if . == "or" then "union" elif . == "and" then "intersection" else . end) as $op |

  (if $op == "union" then
    union_filter(
      $input | filter_by_app_id_regex($app_id_regex) | filter_by_app_id($app_id_filter);
      $input | filter_by_title_regex($title_regex) | filter_by_title($title_filter)
    )
  elif $op == "intersection" then
    intersection_filter(
      $input | filter_by_app_id_regex($app_id_regex) | filter_by_app_id($app_id_filter);
      $input | filter_by_title_regex($title_regex) | filter_by_title($title_filter)
    )
  elif $op == "difference" then
    difference_filter(
      $input | filter_by_app_id_regex($app_id_regex) | filter_by_app_id($app_id_filter);
      $input | filter_by_title_regex($title_regex) | filter_by_title($title_filter)
    )
  elif $op == "or" then
    or_filter(
      $input | filter_by_app_id_regex($app_id_regex) | filter_by_app_id($app_id_filter);
      $input | filter_by_title_regex($title_regex) | filter_by_title($title_filter)
    )
  elif $app_id_regex != "" then
    $input | filter_by_app_id_regex($app_id_regex)
  elif $app_id_filter != "" then
    $input | filter_by_app_id_regex($app_id_regex) | filter_by_app_id($app_id_filter)
  elif $title_regex != "" then
    $input | filter_by_title_regex($title_regex)
  elif $title_filter != "" then
    $input | filter_by_title_regex($title_regex) | filter_by_title($title_filter)
  else
    $input
  end) as $filtered_results |
  
  # sort them by id in ascending order for the focus cycling
  ($filtered_results | sort_by(.id)) as $sorted_results |

  # Apply focus exclusion filter
  ($sorted_results | filter_exclude_focused($exclude_focused)) as $focus_filtered |

  $focus_filtered
  | (if $printdebug == "true" then debug("Filtered results after sort/exclude") else . end)
  | if $list_only == "true" then
      .
    else
      (length) as $len |
      if $len == 0 then
        null
      else
        (map(.id) | sort | unique) as $sorted_ids |
        (map(select(.is_focused == true)) | first) as $focused_window |
        if $focused_window != null then
          ($sorted_ids | index($focused_window.id) // -1) as $current_idx |
          ($current_idx + 1) as $next_idx |
          if $current_idx == -1 or $next_idx >= ($sorted_ids | length) then
            $sorted_ids[0]
          else
            $sorted_ids[$next_idx]
          end
        else
          $sorted_ids[0]
        end
      end
    end;


# Apply filters to the input
apply_filters(
  default_arg("app_id"; "");
  default_arg("title"; "");
  default_arg("app_id_regex"; "");
  default_arg("title_regex"; "");
  default_arg("exclude_focused"; "false");
  default_arg("operation"; "");
  default_arg("printdebug"; "");
  default_arg("list_only"; "false")
)
