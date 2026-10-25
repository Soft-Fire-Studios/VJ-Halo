-- Small authored collision meshes, shared by directional defenses.
-- Geometry is immutable; this module owns no entities, hooks or character data.
local M = {}

function M.Prepare(data)
    local vertices, triangles = {}, {}
    for i, p in ipairs(data.vertices) do vertices[i] = Vector(p[1], p[2], p[3]) end
    local low, high = Vector(vertices[1]), Vector(vertices[1])
    for _, p in ipairs(vertices) do
        low.x, low.y, low.z = math.min(low.x,p.x), math.min(low.y,p.y), math.min(low.z,p.z)
        high.x, high.y, high.z = math.max(high.x,p.x), math.max(high.y,p.y), math.max(high.z,p.z)
    end
    triangles.low, triangles.high = low, high
    for _, face in ipairs(data.triangles) do
        local a, b, c = vertices[face[1]], vertices[face[2]], vertices[face[3]]
        local e1, e2 = b - a, c - a
        local normal = e1:Cross(e2)
        if normal:LengthSqr() > 0.000001 then
            triangles[#triangles + 1] = {a = a, e1 = e1, e2 = e2, normal = normal:GetNormalized()}
        end
    end
    return triangles
end

-- Segment intersection, not a frontal angle check: holes and edges stay open.
function M.Trace(triangles, start, delta)
    -- Slab rejection keeps distant projectiles out of the triangle loop.
    local enter, leave = 0, 1
    local low, high = triangles.low, triangles.high
    for axis = 1, 3 do
        local key = axis == 1 and "x" or axis == 2 and "y" or "z"
        local origin, speed = start[key], delta[key]
        if math.abs(speed) < 0.000001 then
            if origin < low[key] or origin > high[key] then return end
        else
            local a, b = (low[key]-origin)/speed, (high[key]-origin)/speed
            if a > b then a, b = b, a end
            enter, leave = math.max(enter,a), math.min(leave,b)
            if enter > leave then return end
        end
    end
    local nearest, normal
    local dx,dy,dz = delta.x,delta.y,delta.z
    for _, t in ipairs(triangles) do
        local e1,e2 = t.e1,t.e2
        local px,py,pz = dy*e2.z-dz*e2.y,dz*e2.x-dx*e2.z,dx*e2.y-dy*e2.x
        local det = e1.x*px+e1.y*py+e1.z*pz
        if math.abs(det) > 0.000001 then
            local ox,oy,oz = start.x-t.a.x,start.y-t.a.y,start.z-t.a.z
            local u = (ox*px+oy*py+oz*pz)/det
            if u >= -0.00001 and u <= 1.00001 then
                local qx,qy,qz = oy*e1.z-oz*e1.y,oz*e1.x-ox*e1.z,ox*e1.y-oy*e1.x
                local v = (dx*qx+dy*qy+dz*qz)/det
                if v >= -0.00001 and u+v <= 1.00001 then
                    local f = (e2.x*qx+e2.y*qy+e2.z*qz)/det
                    if f >= 0 and f <= 1 and (not nearest or f < nearest) then
                        nearest, normal = f, t.normal
                    end
                end
            end
        end
    end
    if nearest then
        if normal:Dot(delta) > 0 then normal = -normal end
        return nearest, normal
    end
end

return M
