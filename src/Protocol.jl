export MIDIProtocol, MIDIProtocolParams

Base.@kwdef mutable struct MIDIProtocolParams <: ProtocolParams
  filename::Union{Nothing, String} = nothing
end 
MPIMeasurementProtocolParams(dict::Dict) = params_from_dict(MPIMeasurementProtocolParams, dict)

Base.@kwdef mutable struct SingingStepcraft
  robot::MPIMeasurements.StepcraftRobot
  velForNotes::Vector{Int64}
  lowestNote::Int64
  highestNote::Int64
  positionOnStage::Vector{Vector{typeof(1.0u"mm")}} 
  delay::Int64 = 0 #toDo: Measure Delay in ms

  function SingingStepcraft(rob::StepcraftRobot)#,lowestNote::Int) #,highestNote::Int)
    #Hard coded...
    #velForNotes = [1980 2097 2222 2354 2495 2643 2800 2967 3143 3330 3528 3737 3960]
    #range = ["60" "61" "62" "63" "64" "65" "66" "67" "68" "69" "70" "71" "72"] #See MIDI.jl Documentation C=60
    #notes = ["C" "C#" "D" "D#" "E" "F" "F#" "G" "G#" "A" "A#" "B" "c"] 
    highestNote = 48  #toDo: look for better place to place these values
    lowestNote = 84
    range = highestNote-lowestNote
    if range < 0
      error("Highest note should be higher than lowest note")
    end
    if range > 100
      error("Length of velocity is to big (maximum = 100)")
    end
    if maximum(velForNotes) > 10000 #toDo determin maximum Speed, with maximum speed one could detemin whether Stepcraft can always be instantiated with a hard coded lowest an highest note
      error("Highest Note is to high")
    end
    if maximum(velForNotes) < 0 #toDo is there a minimum speed?
      error("Lowest Note is to low")
    end

    velForNotes = zeros(range+1)
    global counter = 1
    for note in lowestNote:highestNote
      velForNotes[counter] = 1980*2^((note-60)/12) #60 is hard coded here because thats the number belonging to the 1980 robot speed
      counter = counter+1
    end

    teachingToSingInTune(rob,velForNotes)
    moveToMiddle(getRobot(protocol.scanner))
    positionOnStage = rob.params.axisRange
    return new(rob,velForNotes,lowestNote,highestNote,positionOnStage)
  end
end

Base.@kwdef mutable struct _MIDIProtocol <: Protocol
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::typeof(MPIMeasurementProtocolParams)
  biChannel::Union{BidirectionalChannel{ProtocolEvent}, Nothing} = nothing
  executeTask::Union{Task, Nothing} = nothing

  midiFile::Union{MIDIFile, Nothing} = nothing
  done::Bool = false
  cancelled::Bool = false
  stopped::Bool = false
  finishAcknowledged::Bool = false

  singingStepcraft::SingingStepcraft = nothing
end

requiredDevices(protocol::_MIDIProtocol) = [StepcraftRobot]

function teachingToSingInTune(rob::StepcraftRobot,velForNotes::Vector)
  for tone = 1:length(velForNotes)
    stepcraftCommand(rob,"#G$tone,$(velForNotes[tone])")
  end
end

function _init(protocol::_MIDIProtocol)
  protocol.midiFile = readMIDIFile(protocol.params.filename)
  protocol.singingStepcraft = SingingStepcraft(getRobot(protocol.scanner))
  checkForPlayablity(protocol)
end

function checkForPlayablity(protocol::_MIDIProtocol)
  notes = getnotes(protocol.midiFile, 1)
  
  for i = 1:length(notes) #Bisschen umständlich. TODO: Bessere Lösung
    if Int(notes[i].pitch)>protocol.singingStepcraft.highestNote || Int(notes[i].pitch)<protocol.singingStepcraft.lowestNote
      error("Notes are out of Stepcraft Range")
    end
    if protocol.singingStepcraft.delay > notes[i].duration
      error("Stepcraft is not fast enough for this song")
    end
  end
end

function moveToMiddle(rob::StepcraftRobot)
  axisRange = rob.params.axisRange
  _moveAbs(rob,axisRange./2)
end

function timeEstimate(protocol::_MIDIProtocol)
  # TODO return track time as string. ?In SECONDS?
  notes = getnotes(protocol.midiFile, 1)
  return String(Int64(round((notes[1].pos-(notes[end].pos+notes[end].duration))/1000)))
end

function enterExecute(protocol::MPIMeasurementProtocol)
  protocol.done = false
  protocol.cancelled = false
  protocol.stopped = false
  protocol.finishAcknowledged = false
end

function _execute(protocol::_MIDIProtocol)
  @info "MIDI protocol started"
  if !isReferenced(getRobot(protocol.scanner))
    throw(IllegalStateException("Robot not referenced! Cannot proceed!"))
  end

  performMusic(protocol)

  put!(protocol.biChannel, FinishedNotificationEvent())
  while !(protocol.finishAcknowledged)
    handleEvents(protocol) 
    protocol.cancelled && throw(CancelException())
    sleep(0.05)
  end

  @info "MIDI protocol finished"
  close(protocol.biChannel)
end

function performMusic(protocol::_MIDIProtocol)
  notes = getnotes(protocol.midiFile, 1)
  #Problem: Synchronisierung von Stepcraft und Code -> Vllt gesamtes Lied direkt an Stepcraft schicken? Wie Pausen? Zuerst nur lansgame Lieder. Zeihe immer delay ab...
  # TODO pseudocode-ish
  for note in notes
    playNote(protocol, note)

    notifiedStop = false
    handleEvents(protocol)
    protocol.cancelled && throw(CancelException())
    while protocol.stopped
      handleEvents(protocol)
      protocol.cancelled && throw(CancelException())
      if !notifiedStop
        put!(protocol.biChannel, OperationSuccessfulEvent(StopEvent()))
        notifiedStop = true
      end
      if !protocol.stopped
        put!(protocol.biChannel, OperationSuccessfulEvent(ResumeEvent()))
      end
      sleep(0.05)
    end
  end
end

function playNote(protocol::_MIDIProtocol, note)
  
end

function cleanup(protocol::_MIDIProtocol)
  # NOP
end

function stop(protocol::_MIDIProtocol)
  protocol.stopped = true
end

function resume(protocol::_MIDIProtocol)
  protocol.stopped = false
end

function cancel(protocol::_MIDIProtocol)
  protocol.cancelled = true
end

function handleEvent(protocol::_MIDIProtocol, event::ProgressQueryEvent)

end

handleEvent(protocol::_MIDIProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true