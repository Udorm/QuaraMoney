import Foundation

/// Currency precision, separated by *purpose*.
///
/// Two different questions get confused with each other, and answering them with
/// one number is how riel ends up 100× off:
///
/// - **How many minor units does this currency have?** An ISO fact. It governs
///   stored `Int64` ledger amounts and anything crossing the wire, where both
///   ends must agree exactly and forever.
/// - **What's the smallest amount a person can actually hand over?** A local
///   practice. It governs *splitting* a bill, where producing 3,333.33៛ is
///   arithmetically fine and practically useless — the smallest riel note in
///   circulation is 100៛.
///
/// KHR is where they diverge: ISO 4217 gives it two minor digits, everyday use
/// gives it none. MitraTrip's `ReceiptSplit` makes the same distinction for the
/// same reason.
enum MoneyPrecision {

    /// Storage and wire precision — **ISO**, and deliberately nothing else.
    ///
    /// This is the number that must never drift: it backs the `Int64` minor
    /// units of the event ledger and of `SharedExpensePayload`. Redefining KHR
    /// here would reinterpret every stored riel row by 100×, so the practice
    /// override lives in `splitFractionDigits` instead and never touches this.
    static func wireFractionDigits(for currencyCode: String) -> Int {
        MoneyMinorUnitConverter.fractionDigits(for: currencyCode)
    }

    /// Currencies whose smallest circulating unit is coarser than ISO implies.
    ///
    /// Splitting to a precision below this produces amounts nobody can settle in
    /// cash. Additive only — a currency listed here still *stores* at its ISO
    /// precision.
    private static let practicalWholeUnitCurrencies: Set<String> = ["KHR"]

    /// Precision for dividing a bill between people.
    ///
    /// ISO, minus the practice overrides above. Zero-decimal currencies (JPY,
    /// KRW) and three-decimal ones (KWD, BHD) therefore resolve correctly rather
    /// than being forced to two.
    static func splitFractionDigits(for currencyCode: String) -> Int {
        let code = currencyCode.uppercased()
        if practicalWholeUnitCurrencies.contains(code) { return 0 }
        return wireFractionDigits(for: code)
    }
}
