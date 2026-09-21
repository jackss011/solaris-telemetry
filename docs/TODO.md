# TODOs

## Telemetry Database
Based on [Cosmos Telemetry v4](https://ballaerospace.github.io/cosmos-website/docs/v4/telemetry)
telemtry packet arrives as []u8
- timestamp it
- map it to a tlm_id (opaque)
- notify tlm_id on event_bus
- from tlm_id, into:
  - name, other base def
  - enumerate tlm_items