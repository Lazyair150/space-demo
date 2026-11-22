# Space × Jar — Order funnel and skill resource-cost semantics

## The funnel is the skill's resource execution proof

A skill binding does not specify a made-up liquid quantity per liquid-bearing Jar. It supplies a Jar order specification and a mapping to a Space effect. Jar receives only its own authoritative requirement contract. The actual liquid amount is derived by Jar from the concrete operation plan and resource manifest.

For A-class skills, the funnel bypasses Slave completely and solves all requirements on Master.

For B-class skills, the funnel is:

1. **Slave filter:** test whether candidate Jars can reach the required states under Slave capabilities, capacity, bans and operation rules. Derive the Slave path's exact required initial free liquid.
2. **Master filter:** assign the remaining requirements and prove Master can execute its own path while retaining the exact liquid amount needed for the Slave.
3. **Transfer proof:** prove one-way Master-to-Slave Jar/liquid handoff fits the Slave capacity and staging peak. Slave has no independent ship-liquid source.
4. **Terminal proof:** every requirement has a concrete Jar destination and every operation/resource balance is valid.

The search order must not become irreversible greedy assignment. If a locally valid Slave placement prevents a complete Master solution, the solver must backtrack. A partial funnel is not a successful skill activation.

## Skill benefit/cost curve

The Space balance model should compare:

- **Benefit:** expected combat/world effect over the battle duration, accounting for cooldown and actual trigger policy.
- **Jar cost:** the actual operation/requirement complexity and resource proof produced by Jar, including Master and Slave constraints.
- **Acquisition cost:** the expected effort to obtain the required Jar shapes/liquids through enemy drops and production devices.
- **Build competition:** competition among all equipped skills for the same ship stock, processor output, workshop roles, staging capacity and logical time.
- **Realization:** how often a skill can actually complete the entire funnel during a battle, not merely how many activations its cooldown permits.

A Space-side recipe estimate may be used before a concrete Jar solve exists, but it must be explicitly labeled as a forecast with a named assumption set. Once a Jar plan/manifest is available, its exact quantities supersede the estimate. Space must not copy forecast-only quantities into Jar requirements.

## Workshop replacement

Master replacement is a separate in-world resource operation, not a skill activation. It stages ship liquid into the target Master within capacity, migrates/reorganizes Jars through Jar's actual operation rules, commits the fixed Master role, and returns unused retired-Master prefill. Liquid inside a Jar, target prefill, order staging and ship inventory are distinct ownership locations.

Space owns when a replacement is requested and how it is presented to the player. Jar owns feasibility, operation chemistry, capacity, accounting and commit semantics.

## Integration requirements

- Consume Jar's immutable solve plan/resource manifest as the authoritative cost proof when available.
- Keep Space's benefit/effect semantics separate from Jar's resource semantics.
- Use one shared simulation clock for combat, cooldowns, production and Jar execution.
- Include the full funnel realization rate in skill value diagnostics.
- Treat Undetermined (for example, solver budget exhaustion) separately from Infeasible.
