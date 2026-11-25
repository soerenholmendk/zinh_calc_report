# ZINH_CALC_REPORT – In-house production time per work center

ABAP report (ALV) that lists production order operations with their standard values, as a basis for calculating in-house production time.

## Selection screen

| Field   | Meaning          | Source       |
|---------|------------------|--------------|
| S_WERKS | Plant            | AUFK-WERKS   |
| S_ARBPL | Work center      | CRHD-ARBPL   |
| S_AUFNR | Production order | AUFK-AUFNR   |

Only production orders (AUFK-AUTYP = 10) and main operations (no sub-operations) are selected.

## How the standard value columns are built

1. The work center's **standard value key** is read (CRHD-VGWTS, e.g. `SAP1`).
2. The key's parameters are read from **TC21-PAR01..PAR06**. Each distinct parameter becomes a column pair: value + unit.
3. The column header is the parameter **keyword** from **TC20T-TXT / TXTLG** in the logon language. This is the same text shown on the order operation screen (e.g. *Setup*, *Machine*, *Labor*).
4. The value is taken from the order operation (**AFVV-VGWnn / VGEnn**), where `nn` is the parameter's position in the standard value key. So the values match what CO03 shows.

Values are per operation base quantity (BMSCH / MEINH), just like on the screen. The order quantity (GAMNG) is shown too, so total time can be calculated.

## Output columns

Plant, Work center, Std. value key, Order, Material, Order qty + unit, Operation, Operation text, Base qty + unit, then one value column and one unit column for each standard value parameter.

## Tables used

AUFK, AFKO, AFVC, AFVV, CRHD, TC21, TC20T

## Installation

Pull with abapGit, or create program `ZINH_CALC_REPORT` in SE38 and paste `src/zinh_calc_report.prog.abap`. Requires ABAP 7.40 SP08 or higher (new Open SQL syntax and inline declarations).
