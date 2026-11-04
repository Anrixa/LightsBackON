extends RefCounted
## Single-player physical sight gate. TargetSelector still chooses what the reticle
## points at, but a wall cannot be clicked through just because an ID is nearby.
## This gate runs both when presenting a candidate and inside the host's range
## callback. It never replaces SessionHost's command validation.

const SURFACE_TOLERANCE_M: float = 0.15
const WORLD_COLLISION_MASK: int = 1


static func can_reach(space: PhysicsDirectSpaceState3D, origin: Vector3, target: Vector3,
		reach_m: float, radius_m: float, excluded: Array[RID] = []) -> bool:
	if target == Vector3.INF or reach_m <= 0.0 or radius_m < 0.0:
		return false
	var distance_m: float = origin.distance_to(target)
	if distance_m > reach_m + radius_m:
		return false
	if distance_m < 0.001:
		return true
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target, WORLD_COLLISION_MASK, excluded)
	query.hit_from_inside = false
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return true
	# The authored marker is just in front of (or a few centimeters inside)
	# its own cabinet/panel surface. Accept that impact, but reject an earlier
	# wall, building or prop hit. Even large aim-assist spheres cannot bypass
	# this thin tolerance.
	return (hit["position"] as Vector3).distance_to(target) <= minf(radius_m, SURFACE_TOLERANCE_M)
