package sim

import (
	"fmt"
)

// ValidateBody checks the fixed-point dimensions shared by authored and
// dynamically spawned entity bodies. Solidity affects wall overlap semantics,
// not whether the dimensions themselves are valid.
func ValidateBody(body Body) error {
	return validateBody(body, "body")
}

func validateBody(body Body, label string) error {
	if body.HalfWidth <= 0 || body.HalfHeight <= 0 {
		return fmt.Errorf("%s dimensions must be positive", label)
	}
	if !validCoord(body.HalfWidth) || !validCoord(body.HalfHeight) {
		return fmt.Errorf("%s is outside deterministic range", label)
	}
	return nil
}

// ValidateWall validates one detached wall definition independently of Config.
// Builders can use it to reject malformed polygon content before constructing
// a Simulation. Stage containment and duplicate identities remain Config-level
// validation.
func ValidateWall(wall Wall) error {
	if wall.ID == "" {
		return fmt.Errorf("wall ID is required")
	}
	return validateWallGeometry(wall, fmt.Sprintf("wall %q", wall.ID))
}

// WallOverlapsRect validates both detached inputs, then performs deterministic
// strict-overlap collision. It is shared by Simulation walls and runtime
// navigation shapes so polygon portals cannot drift from movement semantics.
// Merely touching an edge is not an overlap.
func WallOverlapsRect(wall Wall, rect Rect) (bool, error) {
	if err := ValidateWall(wall); err != nil {
		return false, err
	}
	if err := validateRect(rect, "overlap rectangle"); err != nil {
		return false, err
	}
	return wallOverlapsRect(wall, rect), nil
}

// validateWallGeometry accepts the original rectangle representation and
// strictly convex authored polygons. Polygon bounds are required to be exact:
// collision, rendering, and broad-phase inspection must all describe the same
// immutable shape.
func validateWallGeometry(wall Wall, label string) error {
	if err := validateRect(wall.Rect, label); err != nil {
		return err
	}
	if len(wall.Points) == 0 {
		return nil
	}
	if len(wall.Points) < 3 {
		return fmt.Errorf("%s polygon requires at least three points", label)
	}

	seen := make(map[Vec]struct{}, len(wall.Points))
	bounds := Rect{
		MinX: wall.Points[0].X,
		MinY: wall.Points[0].Y,
		MaxX: wall.Points[0].X,
		MaxY: wall.Points[0].Y,
	}
	for index, point := range wall.Points {
		if !validCoord(point.X) || !validCoord(point.Y) {
			return fmt.Errorf(
				"%s polygon point %d is outside deterministic range",
				label,
				index,
			)
		}
		if _, duplicate := seen[point]; duplicate {
			return fmt.Errorf(
				"%s polygon repeats point %d",
				label,
				index,
			)
		}
		seen[point] = struct{}{}
		bounds.MinX = minCoord(bounds.MinX, point.X)
		bounds.MinY = minCoord(bounds.MinY, point.Y)
		bounds.MaxX = maxCoord(bounds.MaxX, point.X)
		bounds.MaxY = maxCoord(bounds.MaxY, point.Y)
	}
	if bounds != wall.Rect {
		return fmt.Errorf("%s polygon bounds do not match its points", label)
	}

	var turn int64
	for index := range wall.Points {
		a := wall.Points[index]
		b := wall.Points[(index+1)%len(wall.Points)]
		c := wall.Points[(index+2)%len(wall.Points)]
		cross := orientation(a, b, c)
		if cross == 0 {
			return fmt.Errorf(
				"%s polygon has a collinear or zero-length edge",
				label,
			)
		}
		if turn == 0 {
			turn = cross
			continue
		}
		if (turn < 0) != (cross < 0) {
			return fmt.Errorf("%s polygon must be convex", label)
		}
	}

	for left := range wall.Points {
		leftNext := (left + 1) % len(wall.Points)
		for right := left + 1; right < len(wall.Points); right++ {
			rightNext := (right + 1) % len(wall.Points)
			if left == right || leftNext == right || rightNext == left {
				continue
			}
			if segmentsIntersect(
				wall.Points[left],
				wall.Points[leftNext],
				wall.Points[right],
				wall.Points[rightNext],
			) {
				return fmt.Errorf("%s polygon intersects itself", label)
			}
		}
	}
	return nil
}

func orientation(a, b, c Vec) int64 {
	return int64(b.X-a.X)*int64(c.Y-a.Y) -
		int64(b.Y-a.Y)*int64(c.X-a.X)
}

func segmentsIntersect(a, b, c, d Vec) bool {
	abC := orientation(a, b, c)
	abD := orientation(a, b, d)
	cdA := orientation(c, d, a)
	cdB := orientation(c, d, b)
	if oppositeSigns(abC, abD) && oppositeSigns(cdA, cdB) {
		return true
	}
	return (abC == 0 && pointOnSegment(c, a, b)) ||
		(abD == 0 && pointOnSegment(d, a, b)) ||
		(cdA == 0 && pointOnSegment(a, c, d)) ||
		(cdB == 0 && pointOnSegment(b, c, d))
}

func oppositeSigns(left, right int64) bool {
	return (left < 0 && right > 0) || (left > 0 && right < 0)
}

func pointOnSegment(point, start, end Vec) bool {
	return point.X >= minCoord(start.X, end.X) &&
		point.X <= maxCoord(start.X, end.X) &&
		point.Y >= minCoord(start.Y, end.Y) &&
		point.Y <= maxCoord(start.Y, end.Y)
}

// wallOverlapsRect uses strict overlap semantics: touching edges are allowed.
// Polygon collision is deterministic integer SAT against the entity AABB.
func wallOverlapsRect(wall Wall, rect Rect) bool {
	if !overlaps(wall.Rect, rect) {
		return false
	}
	if len(wall.Points) == 0 {
		return true
	}
	center := Vec{
		X: rect.MinX + (rect.MaxX-rect.MinX)/2,
		Y: rect.MinY + (rect.MaxY-rect.MinY)/2,
	}
	halfWidth := (rect.MaxX - rect.MinX) / 2
	halfHeight := (rect.MaxY - rect.MinY) / 2
	for index, start := range wall.Points {
		end := wall.Points[(index+1)%len(wall.Points)]
		axisX := int64(end.Y - start.Y)
		axisY := -int64(end.X - start.X)
		minimum, maximum := polygonProjection(wall.Points, axisX, axisY)
		entityCenter := dot(center, axisX, axisY)
		radius := absInt64(axisX)*int64(halfWidth) +
			absInt64(axisY)*int64(halfHeight)
		if entityCenter+radius <= minimum ||
			entityCenter-radius >= maximum {
			return false
		}
	}
	return true
}

// clampAxisAgainstWall preserves the existing axis-separated slide behavior
// while preventing a large fixed-tick delta from tunneling through a polygon.
// At a collision it returns the nearest representable non-overlapping center.
func clampAxisAgainstWall(
	wall Wall,
	body Body,
	current Coord,
	target Coord,
	fixed Coord,
	horizontal bool,
) Coord {
	if target == current {
		return target
	}
	minimum, maximum, intersects :=
		wallAxisCollisionInterval(wall, body, fixed, horizontal)
	if !intersects {
		return target
	}
	if target > current {
		if current < minimum && target >= minimum {
			return minCoord(target, minimum-1)
		}
		return target
	}
	if current > maximum && target <= maximum {
		return maxCoord(target, maximum+1)
	}
	return target
}

// wallAxisCollisionInterval returns the inclusive integer center-coordinate
// interval in which an AABB overlaps a wall while its other axis stays fixed.
// The continuous SAT inequalities are converted directly to integer bounds;
// no floating-point values or movement-size-dependent stepping are involved.
func wallAxisCollisionInterval(
	wall Wall,
	body Body,
	fixed Coord,
	horizontal bool,
) (Coord, Coord, bool) {
	if len(wall.Points) == 0 {
		if horizontal {
			if fixed+body.HalfHeight <= wall.Rect.MinY ||
				fixed-body.HalfHeight >= wall.Rect.MaxY {
				return 0, 0, false
			}
			return wall.Rect.MinX - body.HalfWidth + 1,
				wall.Rect.MaxX + body.HalfWidth - 1,
				true
		}
		if fixed+body.HalfWidth <= wall.Rect.MinX ||
			fixed-body.HalfWidth >= wall.Rect.MaxX {
			return 0, 0, false
		}
		return wall.Rect.MinY - body.HalfHeight + 1,
			wall.Rect.MaxY + body.HalfHeight - 1,
			true
	}

	minimum := int64(-maxAbsCoord)
	maximum := int64(maxAbsCoord)
	axes := make([][2]int64, 0, len(wall.Points)+2)
	axes = append(axes, [2]int64{1, 0}, [2]int64{0, 1})
	for index, start := range wall.Points {
		end := wall.Points[(index+1)%len(wall.Points)]
		axes = append(axes, [2]int64{
			int64(end.Y - start.Y),
			-int64(end.X - start.X),
		})
	}
	for _, axis := range axes {
		axisX, axisY := axis[0], axis[1]
		projectionMin, projectionMax :=
			polygonProjection(wall.Points, axisX, axisY)
		radius := absInt64(axisX)*int64(body.HalfWidth) +
			absInt64(axisY)*int64(body.HalfHeight)
		lower := projectionMin - radius
		upper := projectionMax + radius

		coefficient := axisY
		constant := axisX * int64(fixed)
		if horizontal {
			coefficient = axisX
			constant = axisY * int64(fixed)
		}
		axisMinimum, axisMaximum, possible :=
			strictLinearIntegerInterval(
				coefficient,
				constant,
				lower,
				upper,
			)
		if !possible {
			return 0, 0, false
		}
		if axisMinimum > minimum {
			minimum = axisMinimum
		}
		if axisMaximum < maximum {
			maximum = axisMaximum
		}
		if minimum > maximum {
			return 0, 0, false
		}
	}
	return Coord(minimum), Coord(maximum), true
}

// strictLinearIntegerInterval solves lower < coefficient*x+constant < upper
// for integer x. coefficient normalization keeps all division denominators
// positive and the strict inequalities preserve edge-touching semantics.
func strictLinearIntegerInterval(
	coefficient int64,
	constant int64,
	lower int64,
	upper int64,
) (int64, int64, bool) {
	if coefficient == 0 {
		if constant <= lower || constant >= upper {
			return 0, 0, false
		}
		return int64(-maxAbsCoord), int64(maxAbsCoord), true
	}
	if coefficient < 0 {
		coefficient = -coefficient
		constant = -constant
		lower, upper = -upper, -lower
	}
	minimum := floorDiv(lower-constant, coefficient) + 1
	maximum := ceilDiv(upper-constant, coefficient) - 1
	return minimum, maximum, minimum <= maximum
}

func floorDiv(numerator, denominator int64) int64 {
	quotient := numerator / denominator
	if numerator%denominator != 0 && numerator < 0 {
		quotient--
	}
	return quotient
}

func ceilDiv(numerator, denominator int64) int64 {
	quotient := numerator / denominator
	if numerator%denominator != 0 && numerator > 0 {
		quotient++
	}
	return quotient
}

func polygonProjection(points []Vec, axisX, axisY int64) (int64, int64) {
	minimum := dot(points[0], axisX, axisY)
	maximum := minimum
	for _, point := range points[1:] {
		value := dot(point, axisX, axisY)
		if value < minimum {
			minimum = value
		}
		if value > maximum {
			maximum = value
		}
	}
	return minimum, maximum
}

func dot(point Vec, axisX, axisY int64) int64 {
	return int64(point.X)*axisX + int64(point.Y)*axisY
}

func absInt64(value int64) int64 {
	if value < 0 {
		return -value
	}
	return value
}

func cloneWall(wall Wall) Wall {
	result := wall
	result.Points = append([]Vec(nil), wall.Points...)
	return result
}

func cloneWalls(walls []Wall) []Wall {
	result := make([]Wall, len(walls))
	for index, wall := range walls {
		result[index] = cloneWall(wall)
	}
	return result
}
