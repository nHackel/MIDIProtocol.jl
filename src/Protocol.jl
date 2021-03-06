export MIDIProtocol, MIDIProtocolParams

Base.@kwdef mutable struct MIDIProtocolParams <: ProtocolParams
  filename::Union{Nothing, String} = nothing
end
MPIMeasurementProtocolParams(dict::Dict) = params_from_dict(MPIMeasurementProtocolParams, dict)

Base.@kwdef mutable struct MIDIProtocol <: Protocol
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::MPIMeasurementProtocolParams
  biChannel::Union{BidirectionalChannel{ProtocolEvent}, Nothing} = nothing
  executeTask::Union{Task, Nothing} = nothing

  midiFile::Union{MIDIFile, Nothing} = nothing
  done::Bool = false
  cancelled::Bool = false
  stopped::Bool = false
  finishAcknowledged::Bool = false
end

requiredDevices(protocol::MIDIProtocol) = [StepCraftRobot]

function _init(protocol::MIDIProtocol)
  protocol.midiFile = load(protocol.params.filename)
  # TODO Check if this file is something we can play
  # TODO setup notes in StepCraftRobot
end

function timeEstimate(protocol::MIDIProtocol)
  # TODO return track time as string
end

function enterExecute(protocol::MPIMeasurementProtocol)
  protocol.done = false
  protocol.cancelled = false
  protocol.stopped = false
  protocol.finishAcknowledged = false
end

function _execute(protocol::MIDIProtocol)
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

function performMusic(protocol::MIDIProtocol)
  notes = getnotes(protocol.midiFile, 1)

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

function playNote(protocol::MIDIProtocol, note)
  # TODO Make some magic
end

function cleanup(protocol::MIDIProtocol)
  # NOP
end

function stop(protocol::MIDIProtocol)
  protocol.stopped = true
end

function resume(protocol::MIDIProtocol)
  protocol.stopped = false
end

function cancel(protocol::MIDIProtocol)
  protocol.cancelled = true
end

function handleEvent(protocol::MIDIProtocol, event::ProgressQueryEvent)

end

handleEvent(protocol::MIDIProtocol, event::FinishedAckEvent) = protocol.finishAcknowledged = true