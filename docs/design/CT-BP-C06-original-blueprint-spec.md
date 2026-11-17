# CT-BP/C06 — Cold Chain original-blueprint correction

Authority: Development Blueprint v1.0 pp.18,20; `docs/evidence/CTL2-BLUEPRINT-RECONCILIATION.md`.

- Canal GRID30, west/east feeder capacity14, six required GRID consumers at 25 PU.
- West starts healthy, east trunk broken; one 4 PU pump must be continuously supplied for 120 host ticks to unlock the east-trunk repair.
- Cold store is a mandatory 5 PU consumer, and is powered through an exclusive GRID or GEN route. GEN8 cannot operate pump4 and cold store5 together; 9/8 overload trips protection after 15 ticks, but must remain recoverable.
- The optional bonus tracks *cumulative cold-store unsupplied ticks* across all interruptions, pausing only while valid safe supply exists, never resetting on restoration; when ticks >= 1200 it is irreversibly missed. The main mission remains completable.
- Authoritative canonical state and strict durable checkpoint validation are conditional on the new C06 rule. Legacy contracts preserve their original mission checkpoint dictionary shape.
- Physical sockets, presentation/controller/human testing, old shipped saves, real two-network Steam sessions and release certification remain HOLD.
