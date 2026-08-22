# File: operators.jq

def union_filter(results1; results2):
  (results1 + results2) | unique_by(.id);

def intersection_filter(results1; results2):
  results1 | map(select(.id as $id | results2 | map(.id) | contains([$id])));

def difference_filter(results1; results2):
  results1 | map(select(.id as $id | results2 | map(.id) | contains([$id]) | not));

def or_filter(results1; results2):
  if (results1 | length) > 0 then results1 else results2 end;
