/// Converts simulation speed to the displayed speed under the project's
/// agreed convention of 0.1 metres per world unit.
int speedKmh(double speedUnitsPerSecond) =>
    (speedUnitsPerSecond.abs() * 0.36).round();
