# Typical ECC material families

Checked against public SAP documentation: 2026-10-06. Expected grains below are guidance for ordinary ECC base tables, not certified keys for a landed extract. Add source-system/client scope and handle CDC versions before testing uniqueness. Confirm actual columns and DDIC keys.

| Table | Expected contents | Typical business grain inside one source/client | Common useful fields to verify |
| --- | --- | --- | --- |
| MARA | General, cross-plant material attributes | MATNR | Material type MTART, group MATKL, base unit MEINS, deletion flag LVORM |
| MARC | Plant-specific material settings | MATNR, WERKS | MRP/procurement parameters, profit center PRCTR; availability varies |
| MAKT | Language-specific material descriptions | MATNR, SPRAS | Short description MAKTX |
| MARM | Alternative material units and conversion factors | MATNR, MEINH | UMREZ, UMREN |
| MARD | Storage-location material data and ECC stock quantities | MATNR, WERKS, LGORT | Separate unrestricted, quality, blocked, and other stock categories |
| MBEW | Material valuation | MATNR, BWKEY, BWTAR | Price control VPRSV, standard STPRS/moving VERPR prices, price unit PEINH, valuation class BKLAS |
| MVKE | Sales-specific material data | MATNR, VKORG, VTWEG | Sales unit and sales organization/distribution-channel attributes |

## Join and interpretation rules

- MARA supplies one general material record; MARC supplies multiple plants. Joining MARC on MATNR alone multiplies transactions unless the requested result intentionally spans plants.
- MAKT requires a language choice. SAP's internal language value may be `E` for English, while an extract may expose a transformed ISO code. Inspect values; do not attach every language to each fact row.
- MARM supplies alternate-to-base conversion. For the standard fields, `base_quantity = alternative_quantity * UMREZ / UMREN`. Confirm the actual unit, nonzero denominator, extraction semantics, and rounding. Never add unlike units or invert the ratio by intuition.
- BWKEY is the valuation area; establish its relationship to WERKS/BUKRS using actual configuration (commonly T001K/T001W), rather than assuming equality. BWTAR distinguishes split valuation. Joining MBEW by material alone can multiply rows or mix valuations.
- STPRS/VERPR are not automatically prices per single unit: apply the verified PEINH and currency convention. Currency normally requires valuation-area/company configuration, not an invented MBEW currency column.
- MARD quantities are stock categories at the extraction's effective state. They are neither lifetime receipts nor necessarily historical month-end balances. Batch, special, consignment, sales-order, and project stock may need other tables. Scope each category explicitly.
- A deletion flag is a business status, distinct from a CDC delete/tombstone. Do not automatically exclude either without establishing the intended report logic.
- Material numbers are identifiers. Keep leading zeros and distinguish the same number across clients/source systems. S/4HANA may support longer material identifiers than traditional ECC.

## ECC versus S/4HANA

These material master families remain useful semantic names, but S/4HANA inventory persistence and compatibility access differ. Raw physical replication can differ from SAP application reads through compatibility views. Do not apply ECC MARD stock assumptions to an unidentified S/4 extract. Read the actual source/replication contract.

## Official sources

- [SAP product duplicate-check table families](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/bc6b9325fedd4344a84412b2195064fa/1bc030a8228d405fbea7016562fa85f1.html) establishes general, plant, storage-location, unit, description, valuation, and sales-data families.
- [SAP Data Services MARA/MAKT tutorial](https://help.sap.com/docs/SAP_DATA_SERVICES/8df1dcdec88b4df2afc3eb1cc954b3dc/578399426d6d1014b3fc9283b0e91070.html) demonstrates the material join and a language restriction. Include client/source scope even where a single-client tutorial omits it.
- [SAP MARM extraction guidance](https://help.sap.com/docs/SUPPORT_CONTENT/nwtech/3362694281.html) documents alternate/base unit factors.
- [SAP S/4HANA material-document archiving](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/8308e6d301d54584a33cd04a9861bc52/75bcb6531de6b64ce10000000a174cb4.html) describes the MATDOC persistence change and compatibility views.

SAP tutorials, APIs, and BW extraction structures are semantic references. They do not certify a raw table's complete column list, primary key, or the user's landed schema.
