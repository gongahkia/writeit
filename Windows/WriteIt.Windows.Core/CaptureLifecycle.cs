namespace WriteIt.Windows.Core;

public enum CapturePhase
{
    Idle,
    Opening,
    Drawing,
    Recognizing,
    Delivering,
    Delivered,
    Failed,
    Dismissing,
}

public sealed class CaptureLifecycle
{
    public CapturePhase Phase { get; private set; } = CapturePhase.Idle;

    public string? Message { get; private set; }

    public bool IsActive => Phase != CapturePhase.Idle;

    public bool Begin()
    {
        if (!TryTransition(CapturePhase.Opening)) return false;
        return TryTransition(CapturePhase.Drawing);
    }

    public bool BeginRecognition() => TryTransition(CapturePhase.Recognizing);

    public bool BeginDelivery() => TryTransition(CapturePhase.Delivering);

    public bool CompleteDelivery(string message)
    {
        if (!TryTransition(CapturePhase.Delivered)) return false;
        Message = message;
        return true;
    }

    public bool Fail(string message)
    {
        if (!TryTransition(CapturePhase.Failed)) return false;
        Message = message;
        return true;
    }

    public bool Dismiss()
    {
        if (Phase == CapturePhase.Idle) return true;
        if (!TryTransition(CapturePhase.Dismissing)) return false;
        return TryTransition(CapturePhase.Idle);
    }

    public bool TryTransition(CapturePhase next)
    {
        if (!AllowsTransition(Phase, next)) return false;
        Phase = next;
        if (next is not CapturePhase.Delivered and not CapturePhase.Failed) Message = null;
        return true;
    }

    public static bool AllowsTransition(CapturePhase current, CapturePhase next) => (current, next) switch
    {
        (CapturePhase.Idle, CapturePhase.Opening) => true,
        (CapturePhase.Opening, CapturePhase.Drawing or CapturePhase.Dismissing) => true,
        (CapturePhase.Drawing, CapturePhase.Recognizing or CapturePhase.Dismissing) => true,
        (CapturePhase.Recognizing, CapturePhase.Delivering or CapturePhase.Failed or CapturePhase.Dismissing) => true,
        (CapturePhase.Delivering, CapturePhase.Delivered or CapturePhase.Dismissing) => true,
        (CapturePhase.Delivered or CapturePhase.Failed, CapturePhase.Dismissing) => true,
        (CapturePhase.Dismissing, CapturePhase.Idle) => true,
        _ => false,
    };
}
