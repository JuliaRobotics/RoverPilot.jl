using Base

export saveImage, append!, poseIndex, odoDiff
export RoverPose

struct RoverImage
    timestamp::Float64
    camJpeg::AbstractString
end

mutable struct RoverPose
    poseId::String
    poseIndex::Int64
    timestamp::Float64
    x::Float64
    y::Float64
    theta::Float64
    camImages::Vector{RoverImage}
    prevPose::Nullable{RoverPose}
    # Other stuff like AprilTags here

    # RoverPose(timestamp::Float64, locX::Float64, locY::Float64, theta::Float64, camJpeg::AbstractString) = new(timestamp, locX, locY, theta, camJpeg)
    RoverPose(prevPose::RoverPose) = new(string(Base.Random.uuid4()), prevPose.poseIndex+1, prevPose.timestamp, prevPose.x, prevPose.y, prevPose.theta, Vector{RoverImage}(), prevPose);
    RoverPose() = new(string(Base.Random.uuid4()), 1, 0, 0, 0, 0, Vector{RoverImage}(0), Nullable{RoverPose}());
end

Base.show(io::IO, roverPose::RoverPose) = @printf "[%0.3f] (%s) %s: At (%0.2f, %0.2f) with heading %0.2f, delta %s, and %d images" roverPose.timestamp roverPose.poseId string(poseIndex(roverPose)) roverPose.x roverPose.y roverPose.theta string(odoDiff(roverPose)) length(roverPose.camImages);

"""
Save an image to a file.
"""
function saveImage(roverImage :: RoverImage, imFile :: AbstractString)
    out = open(imFile,"w")
    write(out,roverImage.camJpeg)
    close(out)
end

"""
Returns the pose index symbol, e.g. x1.
"""
function poseIndex(roverPose::RoverPose)
    return Symbol("x"*string(roverPose.poseIndex))
end

"""
Returns the diff (dx, dy, dtheta) between roverPose and roverPose.prevPose.
If no prevPose, assumes origin is (0,0,0).
"""
function odoDiff(roverPose::RoverPose)
    if isnull(roverPose.prevPose)
        return [roverPose.x, roverPose.y, roverPose.theta]
    end
    prevPose = get(roverPose.prevPose)

    return [roverPose.x - prevPose.x, roverPose.y - prevPose.y, roverPose.theta - prevPose.theta]
end

"""
Append the state to this pose, increasing the movement by the given update and adding in the sensory data.
"""
function append!(roverPose::RoverPose, newRoverState::PyCall.PyObject, maxImages = 100)
    duration = newRoverState[:getDuration]()
    endTime = newRoverState[:getEndTime]()
    jpegBytes = newRoverState[:getImage]()
    push!(roverPose.camImages, RoverImage(endTime, jpegBytes))
    while(length(roverPose.camImages) > maxImages)
        pop!(roverPose.camImages)
    end
    # Timestamp
    roverPose.timestamp = endTime
    # Should be either rotation or translation but not both at same time
    roverPose.theta += duration * newRoverState[:getRotSpeedNorm]()
    roverPose.x -= duration * sin(roverPose.theta) * newRoverState[:getTransSpeedNorm]()
    roverPose.y += duration * cos(roverPose.theta) * newRoverState[:getTransSpeedNorm]()
    #println("Duration = $(duration), updated position = $(roverPose.x), $(roverPose.y)")
end

function isPoseWorthy(roverPose::RoverPose)
    # If no previous pose, always true
    if isnull(roverPose.prevPose)
        return true
    end
    prevPose = get(roverPose.prevPose)

    deltaT = roverPose.timestamp - prevPose.timestamp
    deltaDist = sqrt((roverPose.x - prevPose.x)^2 + (roverPose.y - prevPose.y)^2)
    deltaAbsAngRad = abs(roverPose.theta - prevPose.theta)
    while deltaAbsAngRad < 0
        deltaAbsAngRad += 2.0*pi
    end
    while deltaAbsAngRad > 2.0*pi
        deltaAbsAngRad -= 2.0*pi
    end
    return deltaT > 20 || deltaDist > 0.5 || deltaAbsAngRad > pi / 8
end

println("Thanks for importing RoverPose :)")
