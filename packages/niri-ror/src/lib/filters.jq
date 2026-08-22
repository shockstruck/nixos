#!/usr/bin/env jq -f

def filter_by_app_id($filter_string):
  if type == "array" then
    map(
      select(.app_id | type == "string" and contains($filter_string))
      | { id, app_id, title, workspace_id, is_focused }
    )
  elif type == "object" then
    [{ error: "Root is an object, not an array", keys: keys }]
  else
    [{ error: "Unexpected type", type: type }]
  end;

def filter_by_app_id_regex($pattern):
  if $pattern == "" then
    .
  elif type == "array" then
    (try
      map(
        select(.app_id | type == "string" and test($pattern))
        | { id, app_id, title, workspace_id, is_focused }
      )
    catch
      error("Invalid app_id_regex: " + (.|tostring))
    )
  elif type == "object" then
    [{ error: "Root is an object, not an array", keys: keys }]
  else
    [{ error: "Unexpected type", type: type }]
  end;

def filter_by_title($filter_string):
  if type == "array" then
    map(
      select(.title | type == "string" and contains($filter_string))
      | { id, app_id, title, workspace_id, is_focused }
    )
  elif type == "object" then
    [{ error: "Root is an object, not an array", keys: keys }]
  else
    [{ error: "Unexpected type", type: type }]
  end;

def filter_by_title_regex($pattern):
  if $pattern == "" then
    .
  elif type == "array" then
    (try
      map(
        select(.title | type == "string" and test($pattern))
        | { id, app_id, title, workspace_id, is_focused }
      )
    catch
      error("Invalid title_regex: " + (.|tostring))
    )
  elif type == "object" then
    [{ error: "Root is an object, not an array", keys: keys }]
  else
    [{ error: "Unexpected type", type: type }]
  end;

def filter_exclude_focused($exclude_focused):
  if type == "array" then
    if $exclude_focused == "true" then
      map(select(.is_focused != true))
    else
      .  # If $exclude_focused is not "true", return all results
    end
  elif type == "object" then
    [{ error: "Root is an object, not an array", keys: keys }]
  else
    [{ error: "Unexpected type", type: type }]
  end;
