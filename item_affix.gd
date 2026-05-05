extends Resource
class_name ItemAffix

# A rolled affix instance. Lives on an inventory item alongside the
# baseline ItemMetadata; the affix_id keys back into affix_db.gd for
# the prefix/suffix word table and tier definitions.

@export var affix_id: String = ""           # e.g. "sharp", "of_health"
@export var is_prefix: bool = true          # false = suffix
@export var tier: int = 1                   # 1..N, drives roll range
@export var rolled_value: int = 0           # the actual stat number rolled
