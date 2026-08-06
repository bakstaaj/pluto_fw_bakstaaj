# APRS TX Debug Guard Rail

This guard rail applies to every Pluto APRS transmit debugging session.

## Mandatory Success Gate

The APRS TX work is **not complete** until all of these are true:

1. The Pluto transmits the packet through the live RF path.
2. The RTL receiver captures that RF at the configured APRS frequency.
3. The captured demodulated audio is fed to Dire Wolf.
4. Dire Wolf decodes the expected packet successfully.

## Required Behavior

- If Dire Wolf does not decode the expected packet, continue working autonomously.
- Do not pause for user input merely to report progress.
- Do not call the work solved, complete, release-ready, or validated.
- Do not stop after proving only internal audio, IIO throughput, carrier presence, or AFSK-looking spectrum.
- Before ending any work turn, reread this file and verify the Dire Wolf success gate.
- If the gate is not met, take another concrete diagnostic or implementation action before ending.

## Evidence To Record

- Pluto firmware/build identifier and deployed binary.
- TX frequency, sample rate, gain, deviation, and audio source.
- RTL device serial, requested tuner frequency, and actual tuned frequency.
- Dire Wolf configuration and exact decoded frame.
- Raw or demodulated capture path used for the decode.
