# Repository guidance for coding assistants

## OurBox naming (source of truth)

OurBox naming follows **Model → Trim → SKU**:

- **Model** = size/form-factor class (physical contract).
- **Trim** = intent label.
- **SKU** = exact BOM + software build, including incidental variants like color, capacity, or vendor.

SKU identifiers are manufacturer part numbers and **must** begin with `TOO-`.

Reference: [`hw/docs/decisions/ADR-0001-ourbox-model-trim-sku-part-numbers.md`](./hw/docs/decisions/ADR-0001-ourbox-model-trim-sku-part-numbers.md)

## Validation

Run `npm test` to ensure legacy identifiers are not present.
