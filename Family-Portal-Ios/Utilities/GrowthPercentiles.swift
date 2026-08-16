import Foundation

/// WHO 2006 Child Growth Standards (0–24 months) and CDC NCHS 2000 Growth Charts
/// (2–20 years), ported from `frontend/lib/growthPercentiles.ts` so a percentile
/// quoted on the phone matches the one quoted on the web for the same record.
///
/// Every table is **metric** — height in cm, weight in kg — because that is how
/// both standards publish them. Values measured in inches or pounds are converted
/// before they are ranked; see `MeasurementConversion`.
struct PercentileRow: Equatable {
    var month: Double
    var p3: Double
    var p15: Double
    var p50: Double
    var p85: Double
    var p97: Double
}

enum GrowthPercentiles {

    /// The oldest age either standard covers. Past this there is no reference
    /// population, so a percentile is not "100th" — it does not exist.
    static let maxAgeMonths: Double = 240

    /// Where the WHO tables hand over to the CDC ones. Both publish a row at 24
    /// months and they disagree slightly; the web picks WHO for exactly 24, so
    /// the comparison is `<=` here too.
    static let whoCutoffMonths: Double = 24

    // MARK: - WHO 0–24 months

    /// WHO Boys Length-for-age (cm)
    static let whoHeightBoys: [PercentileRow] = [
        PercentileRow(month: 0, p3: 46.1, p15: 47.9, p50: 49.9, p85: 51.9, p97: 53.7),
        PercentileRow(month: 1, p3: 50.8, p15: 52.8, p50: 54.7, p85: 56.7, p97: 58.6),
        PercentileRow(month: 2, p3: 54.4, p15: 56.4, p50: 58.4, p85: 60.4, p97: 62.4),
        PercentileRow(month: 3, p3: 57.3, p15: 59.4, p50: 61.4, p85: 63.5, p97: 65.5),
        PercentileRow(month: 4, p3: 59.7, p15: 61.8, p50: 63.9, p85: 66.0, p97: 68.0),
        PercentileRow(month: 5, p3: 61.7, p15: 63.8, p50: 65.9, p85: 68.0, p97: 70.1),
        PercentileRow(month: 6, p3: 63.3, p15: 65.5, p50: 67.6, p85: 69.8, p97: 71.9),
        PercentileRow(month: 7, p3: 64.8, p15: 67.0, p50: 69.2, p85: 71.4, p97: 73.5),
        PercentileRow(month: 8, p3: 66.2, p15: 68.4, p50: 70.6, p85: 72.9, p97: 75.0),
        PercentileRow(month: 9, p3: 67.5, p15: 69.7, p50: 72.0, p85: 74.3, p97: 76.5),
        PercentileRow(month: 10, p3: 68.7, p15: 71.0, p50: 73.3, p85: 75.6, p97: 77.9),
        PercentileRow(month: 11, p3: 69.9, p15: 72.2, p50: 74.5, p85: 76.9, p97: 79.2),
        PercentileRow(month: 12, p3: 71.0, p15: 73.4, p50: 75.7, p85: 78.1, p97: 80.5),
        PercentileRow(month: 13, p3: 72.1, p15: 74.5, p50: 76.9, p85: 79.3, p97: 81.8),
        PercentileRow(month: 14, p3: 73.1, p15: 75.6, p50: 78.0, p85: 80.5, p97: 83.0),
        PercentileRow(month: 15, p3: 74.1, p15: 76.6, p50: 79.1, p85: 81.7, p97: 84.2),
        PercentileRow(month: 16, p3: 75.0, p15: 77.6, p50: 80.2, p85: 82.8, p97: 85.4),
        PercentileRow(month: 17, p3: 75.9, p15: 78.6, p50: 81.2, p85: 83.9, p97: 86.5),
        PercentileRow(month: 18, p3: 76.9, p15: 79.6, p50: 82.3, p85: 85.0, p97: 87.7),
        PercentileRow(month: 19, p3: 77.7, p15: 80.5, p50: 83.2, p85: 86.0, p97: 88.8),
        PercentileRow(month: 20, p3: 78.6, p15: 81.4, p50: 84.2, p85: 87.0, p97: 89.9),
        PercentileRow(month: 21, p3: 79.4, p15: 82.3, p50: 85.1, p85: 88.0, p97: 90.9),
        PercentileRow(month: 22, p3: 80.2, p15: 83.1, p50: 86.0, p85: 88.9, p97: 91.9),
        PercentileRow(month: 23, p3: 81.0, p15: 83.9, p50: 86.9, p85: 89.8, p97: 92.9),
        PercentileRow(month: 24, p3: 81.7, p15: 84.7, p50: 87.8, p85: 90.9, p97: 93.9),
    ]

    /// WHO Girls Length-for-age (cm)
    static let whoHeightGirls: [PercentileRow] = [
        PercentileRow(month: 0, p3: 45.4, p15: 47.2, p50: 49.1, p85: 51.1, p97: 52.9),
        PercentileRow(month: 1, p3: 49.8, p15: 51.8, p50: 53.7, p85: 55.7, p97: 57.6),
        PercentileRow(month: 2, p3: 53.0, p15: 55.0, p50: 57.1, p85: 59.1, p97: 61.1),
        PercentileRow(month: 3, p3: 55.6, p15: 57.7, p50: 59.8, p85: 61.9, p97: 63.9),
        PercentileRow(month: 4, p3: 57.8, p15: 59.9, p50: 62.1, p85: 64.2, p97: 66.3),
        PercentileRow(month: 5, p3: 59.6, p15: 61.8, p50: 64.0, p85: 66.2, p97: 68.4),
        PercentileRow(month: 6, p3: 61.2, p15: 63.4, p50: 65.7, p85: 67.9, p97: 70.2),
        PercentileRow(month: 7, p3: 62.7, p15: 65.0, p50: 67.3, p85: 69.6, p97: 71.9),
        PercentileRow(month: 8, p3: 64.0, p15: 66.4, p50: 68.7, p85: 71.1, p97: 73.5),
        PercentileRow(month: 9, p3: 65.3, p15: 67.7, p50: 70.1, p85: 72.6, p97: 74.9),
        PercentileRow(month: 10, p3: 66.5, p15: 68.9, p50: 71.5, p85: 73.9, p97: 76.4),
        PercentileRow(month: 11, p3: 67.7, p15: 70.2, p50: 72.8, p85: 75.3, p97: 77.8),
        PercentileRow(month: 12, p3: 68.9, p15: 71.5, p50: 74.0, p85: 76.6, p97: 79.2),
        PercentileRow(month: 13, p3: 70.0, p15: 72.6, p50: 75.2, p85: 77.8, p97: 80.5),
        PercentileRow(month: 14, p3: 71.0, p15: 73.7, p50: 76.4, p85: 79.1, p97: 81.8),
        PercentileRow(month: 15, p3: 72.0, p15: 74.8, p50: 77.5, p85: 80.3, p97: 83.1),
        PercentileRow(month: 16, p3: 73.0, p15: 75.8, p50: 78.6, p85: 81.5, p97: 84.3),
        PercentileRow(month: 17, p3: 73.9, p15: 76.8, p50: 79.7, p85: 82.6, p97: 85.5),
        PercentileRow(month: 18, p3: 74.9, p15: 77.8, p50: 80.7, p85: 83.6, p97: 86.5),
        PercentileRow(month: 19, p3: 75.7, p15: 78.7, p50: 81.7, p85: 84.7, p97: 87.7),
        PercentileRow(month: 20, p3: 76.5, p15: 79.6, p50: 82.7, p85: 85.8, p97: 88.9),
        PercentileRow(month: 21, p3: 77.3, p15: 80.5, p50: 83.6, p85: 86.7, p97: 90.0),
        PercentileRow(month: 22, p3: 78.1, p15: 81.3, p50: 84.6, p85: 87.7, p97: 91.1),
        PercentileRow(month: 23, p3: 78.9, p15: 82.1, p50: 85.5, p85: 88.7, p97: 92.2),
        PercentileRow(month: 24, p3: 79.6, p15: 83.0, p50: 86.4, p85: 89.8, p97: 93.3),
    ]

    /// WHO Boys Weight-for-age (kg)
    static let whoWeightBoys: [PercentileRow] = [
        PercentileRow(month: 0, p3: 2.5, p15: 2.9, p50: 3.3, p85: 3.9, p97: 4.4),
        PercentileRow(month: 1, p3: 3.4, p15: 3.9, p50: 4.5, p85: 5.1, p97: 5.8),
        PercentileRow(month: 2, p3: 4.4, p15: 4.9, p50: 5.6, p85: 6.3, p97: 7.1),
        PercentileRow(month: 3, p3: 5.1, p15: 5.7, p50: 6.4, p85: 7.2, p97: 8.0),
        PercentileRow(month: 4, p3: 5.6, p15: 6.2, p50: 7.0, p85: 7.9, p97: 8.7),
        PercentileRow(month: 5, p3: 6.1, p15: 6.7, p50: 7.5, p85: 8.4, p97: 9.3),
        PercentileRow(month: 6, p3: 6.4, p15: 7.1, p50: 7.9, p85: 8.8, p97: 9.8),
        PercentileRow(month: 7, p3: 6.7, p15: 7.4, p50: 8.3, p85: 9.2, p97: 10.3),
        PercentileRow(month: 8, p3: 7.0, p15: 7.7, p50: 8.6, p85: 9.6, p97: 10.7),
        PercentileRow(month: 9, p3: 7.2, p15: 8.0, p50: 8.9, p85: 9.9, p97: 11.0),
        PercentileRow(month: 10, p3: 7.5, p15: 8.2, p50: 9.2, p85: 10.2, p97: 11.4),
        PercentileRow(month: 11, p3: 7.7, p15: 8.4, p50: 9.4, p85: 10.5, p97: 11.7),
        PercentileRow(month: 12, p3: 7.8, p15: 8.6, p50: 9.6, p85: 10.8, p97: 12.0),
        PercentileRow(month: 13, p3: 8.0, p15: 8.8, p50: 9.9, p85: 11.1, p97: 12.3),
        PercentileRow(month: 14, p3: 8.2, p15: 9.0, p50: 10.1, p85: 11.3, p97: 12.6),
        PercentileRow(month: 15, p3: 8.4, p15: 9.2, p50: 10.3, p85: 11.6, p97: 12.9),
        PercentileRow(month: 16, p3: 8.5, p15: 9.4, p50: 10.5, p85: 11.8, p97: 13.2),
        PercentileRow(month: 17, p3: 8.7, p15: 9.6, p50: 10.8, p85: 12.1, p97: 13.5),
        PercentileRow(month: 18, p3: 8.8, p15: 9.7, p50: 10.9, p85: 12.3, p97: 13.7),
        PercentileRow(month: 19, p3: 9.0, p15: 9.9, p50: 11.1, p85: 12.5, p97: 14.0),
        PercentileRow(month: 20, p3: 9.2, p15: 10.1, p50: 11.3, p85: 12.7, p97: 14.2),
        PercentileRow(month: 21, p3: 9.3, p15: 10.3, p50: 11.5, p85: 13.0, p97: 14.5),
        PercentileRow(month: 22, p3: 9.5, p15: 10.5, p50: 11.8, p85: 13.2, p97: 14.8),
        PercentileRow(month: 23, p3: 9.7, p15: 10.7, p50: 12.0, p85: 13.5, p97: 15.1),
        PercentileRow(month: 24, p3: 9.8, p15: 10.8, p50: 12.2, p85: 13.7, p97: 15.3),
    ]

    /// WHO Girls Weight-for-age (kg)
    static let whoWeightGirls: [PercentileRow] = [
        PercentileRow(month: 0, p3: 2.4, p15: 2.8, p50: 3.2, p85: 3.7, p97: 4.2),
        PercentileRow(month: 1, p3: 3.2, p15: 3.6, p50: 4.2, p85: 4.8, p97: 5.5),
        PercentileRow(month: 2, p3: 4.0, p15: 4.5, p50: 5.1, p85: 5.8, p97: 6.6),
        PercentileRow(month: 3, p3: 4.6, p15: 5.2, p50: 5.8, p85: 6.6, p97: 7.5),
        PercentileRow(month: 4, p3: 5.1, p15: 5.7, p50: 6.4, p85: 7.3, p97: 8.2),
        PercentileRow(month: 5, p3: 5.5, p15: 6.1, p50: 6.9, p85: 7.8, p97: 8.8),
        PercentileRow(month: 6, p3: 5.7, p15: 6.5, p50: 7.3, p85: 8.2, p97: 9.3),
        PercentileRow(month: 7, p3: 6.0, p15: 6.8, p50: 7.6, p85: 8.6, p97: 9.8),
        PercentileRow(month: 8, p3: 6.3, p15: 7.0, p50: 7.9, p85: 9.0, p97: 10.2),
        PercentileRow(month: 9, p3: 6.5, p15: 7.3, p50: 8.2, p85: 9.3, p97: 10.5),
        PercentileRow(month: 10, p3: 6.7, p15: 7.5, p50: 8.5, p85: 9.6, p97: 10.9),
        PercentileRow(month: 11, p3: 6.9, p15: 7.7, p50: 8.7, p85: 9.9, p97: 11.2),
        PercentileRow(month: 12, p3: 7.1, p15: 7.9, p50: 8.9, p85: 10.1, p97: 11.5),
        PercentileRow(month: 13, p3: 7.2, p15: 8.1, p50: 9.2, p85: 10.4, p97: 11.8),
        PercentileRow(month: 14, p3: 7.4, p15: 8.3, p50: 9.4, p85: 10.7, p97: 12.1),
        PercentileRow(month: 15, p3: 7.6, p15: 8.5, p50: 9.6, p85: 10.9, p97: 12.4),
        PercentileRow(month: 16, p3: 7.7, p15: 8.7, p50: 9.8, p85: 11.2, p97: 12.7),
        PercentileRow(month: 17, p3: 7.9, p15: 8.9, p50: 10.0, p85: 11.4, p97: 13.0),
        PercentileRow(month: 18, p3: 8.1, p15: 9.1, p50: 10.2, p85: 11.7, p97: 13.2),
        PercentileRow(month: 19, p3: 8.2, p15: 9.2, p50: 10.4, p85: 11.9, p97: 13.5),
        PercentileRow(month: 20, p3: 8.4, p15: 9.4, p50: 10.6, p85: 12.1, p97: 13.7),
        PercentileRow(month: 21, p3: 8.6, p15: 9.6, p50: 10.9, p85: 12.4, p97: 14.0),
        PercentileRow(month: 22, p3: 8.7, p15: 9.8, p50: 11.1, p85: 12.6, p97: 14.3),
        PercentileRow(month: 23, p3: 8.9, p15: 10.0, p50: 11.3, p85: 12.9, p97: 14.6),
        PercentileRow(month: 24, p3: 9.0, p15: 10.2, p50: 11.5, p85: 13.1, p97: 14.9),
    ]

    // MARK: - CDC 2–20 years

    /// CDC NCHS 2000 Boys Stature-for-age (cm), annual from 24–240 months
    static let cdcHeightBoys: [PercentileRow] = [
        PercentileRow(month: 24, p3: 82.3, p15: 85.1, p50: 87.6, p85: 90.2, p97: 93.0),
        PercentileRow(month: 36, p3: 89.0, p15: 92.4, p50: 95.7, p85: 98.9, p97: 101.9),
        PercentileRow(month: 48, p3: 95.4, p15: 99.1, p50: 102.9, p85: 106.6, p97: 110.1),
        PercentileRow(month: 60, p3: 101.5, p15: 105.5, p50: 109.4, p85: 113.5, p97: 117.4),
        PercentileRow(month: 72, p3: 107.1, p15: 111.4, p50: 115.5, p85: 119.8, p97: 124.1),
        PercentileRow(month: 84, p3: 112.1, p15: 116.7, p50: 121.1, p85: 125.7, p97: 130.4),
        PercentileRow(month: 96, p3: 117.0, p15: 121.8, p50: 126.6, p85: 131.6, p97: 136.8),
        PercentileRow(month: 108, p3: 121.5, p15: 126.6, p50: 131.8, p85: 137.3, p97: 142.9),
        PercentileRow(month: 120, p3: 125.7, p15: 131.1, p50: 136.9, p85: 142.9, p97: 149.2),
        PercentileRow(month: 132, p3: 129.5, p15: 135.3, p50: 141.6, p85: 148.3, p97: 155.3),
        PercentileRow(month: 144, p3: 133.5, p15: 139.7, p50: 146.8, p85: 154.4, p97: 162.1),
        PercentileRow(month: 156, p3: 138.8, p15: 145.8, p50: 153.5, p85: 161.4, p97: 169.0),
        PercentileRow(month: 168, p3: 144.6, p15: 151.9, p50: 159.9, p85: 167.9, p97: 175.3),
        PercentileRow(month: 180, p3: 150.0, p15: 157.4, p50: 165.3, p85: 172.9, p97: 179.8),
        PercentileRow(month: 192, p3: 154.0, p15: 161.3, p50: 169.2, p85: 176.6, p97: 183.0),
        PercentileRow(month: 204, p3: 156.6, p15: 163.7, p50: 171.6, p85: 178.7, p97: 184.9),
        PercentileRow(month: 216, p3: 158.1, p15: 165.1, p50: 173.1, p85: 179.9, p97: 185.8),
        PercentileRow(month: 228, p3: 158.9, p15: 165.9, p50: 173.9, p85: 180.5, p97: 186.2),
        PercentileRow(month: 240, p3: 159.0, p15: 166.0, p50: 174.0, p85: 180.6, p97: 186.2),
    ]

    /// CDC NCHS 2000 Girls Stature-for-age (cm), annual from 24–240 months
    static let cdcHeightGirls: [PercentileRow] = [
        PercentileRow(month: 24, p3: 80.9, p15: 83.7, p50: 86.4, p85: 89.1, p97: 91.9),
        PercentileRow(month: 36, p3: 88.3, p15: 91.7, p50: 94.9, p85: 98.2, p97: 101.5),
        PercentileRow(month: 48, p3: 94.4, p15: 98.0, p50: 101.6, p85: 105.3, p97: 109.0),
        PercentileRow(month: 60, p3: 100.1, p15: 104.0, p50: 107.9, p85: 111.9, p97: 115.9),
        PercentileRow(month: 72, p3: 105.4, p15: 109.6, p50: 113.7, p85: 117.9, p97: 122.2),
        PercentileRow(month: 84, p3: 110.5, p15: 115.0, p50: 119.4, p85: 124.0, p97: 128.9),
        PercentileRow(month: 96, p3: 115.4, p15: 120.2, p50: 124.9, p85: 129.9, p97: 135.2),
        PercentileRow(month: 108, p3: 120.1, p15: 125.2, p50: 130.3, p85: 135.7, p97: 141.4),
        PercentileRow(month: 120, p3: 124.6, p15: 130.2, p50: 135.7, p85: 141.7, p97: 148.1),
        PercentileRow(month: 132, p3: 129.3, p15: 135.4, p50: 141.7, p85: 148.5, p97: 155.7),
        PercentileRow(month: 144, p3: 134.9, p15: 141.5, p50: 148.3, p85: 155.4, p97: 162.7),
        PercentileRow(month: 156, p3: 140.0, p15: 146.8, p50: 153.7, p85: 160.5, p97: 167.3),
        PercentileRow(month: 168, p3: 143.9, p15: 150.5, p50: 157.2, p85: 163.6, p97: 170.2),
        PercentileRow(month: 180, p3: 146.4, p15: 152.7, p50: 159.2, p85: 165.5, p97: 171.8),
        PercentileRow(month: 192, p3: 147.7, p15: 153.8, p50: 160.2, p85: 166.4, p97: 172.5),
        PercentileRow(month: 204, p3: 148.3, p15: 154.4, p50: 160.8, p85: 166.9, p97: 173.0),
        PercentileRow(month: 216, p3: 148.5, p15: 154.7, p50: 161.2, p85: 167.3, p97: 173.4),
        PercentileRow(month: 228, p3: 148.7, p15: 154.9, p50: 161.3, p85: 167.5, p97: 173.5),
        PercentileRow(month: 240, p3: 148.7, p15: 154.9, p50: 161.3, p85: 167.5, p97: 173.5),
    ]

    /// CDC NCHS 2000 Boys Weight-for-age (kg), annual from 24–240 months
    static let cdcWeightBoys: [PercentileRow] = [
        PercentileRow(month: 24, p3: 10.5, p15: 11.6, p50: 12.9, p85: 14.5, p97: 16.4),
        PercentileRow(month: 36, p3: 12.1, p15: 13.5, p50: 14.9, p85: 17.1, p97: 19.7),
        PercentileRow(month: 48, p3: 13.7, p15: 15.3, p50: 16.9, p85: 19.7, p97: 22.7),
        PercentileRow(month: 60, p3: 15.3, p15: 17.1, p50: 19.0, p85: 22.2, p97: 25.8),
        PercentileRow(month: 72, p3: 17.0, p15: 19.1, p50: 21.5, p85: 25.3, p97: 29.7),
        PercentileRow(month: 84, p3: 18.8, p15: 21.2, p50: 24.2, p85: 28.9, p97: 34.7),
        PercentileRow(month: 96, p3: 20.6, p15: 23.5, p50: 27.3, p85: 32.8, p97: 40.3),
        PercentileRow(month: 108, p3: 22.4, p15: 25.9, p50: 30.7, p85: 37.5, p97: 46.7),
        PercentileRow(month: 120, p3: 24.4, p15: 28.5, p50: 34.3, p85: 42.4, p97: 53.8),
        PercentileRow(month: 132, p3: 26.7, p15: 31.5, p50: 38.3, p85: 47.7, p97: 61.0),
        PercentileRow(month: 144, p3: 29.7, p15: 35.4, p50: 43.1, p85: 53.6, p97: 68.5),
        PercentileRow(month: 156, p3: 33.8, p15: 40.3, p50: 48.9, p85: 60.3, p97: 76.4),
        PercentileRow(month: 168, p3: 38.5, p15: 45.6, p50: 55.0, p85: 67.1, p97: 84.3),
        PercentileRow(month: 180, p3: 43.1, p15: 50.7, p50: 60.7, p85: 73.1, p97: 91.1),
        PercentileRow(month: 192, p3: 47.2, p15: 55.2, p50: 65.5, p85: 78.3, p97: 97.1),
        PercentileRow(month: 204, p3: 50.8, p15: 59.1, p50: 69.8, p85: 83.2, p97: 102.8),
        PercentileRow(month: 216, p3: 53.8, p15: 62.5, p50: 73.5, p85: 87.5, p97: 107.9),
        PercentileRow(month: 228, p3: 56.0, p15: 65.0, p50: 76.3, p85: 90.8, p97: 111.9),
        PercentileRow(month: 240, p3: 57.4, p15: 66.7, p50: 78.1, p85: 92.8, p97: 114.8),
    ]

    /// CDC NCHS 2000 Girls Weight-for-age (kg), annual from 24–240 months
    static let cdcWeightGirls: [PercentileRow] = [
        PercentileRow(month: 24, p3: 10.1, p15: 11.2, p50: 12.5, p85: 14.0, p97: 15.9),
        PercentileRow(month: 36, p3: 11.6, p15: 13.0, p50: 14.6, p85: 16.5, p97: 18.9),
        PercentileRow(month: 48, p3: 13.1, p15: 14.8, p50: 16.7, p85: 19.1, p97: 22.0),
        PercentileRow(month: 60, p3: 14.6, p15: 16.5, p50: 18.8, p85: 21.8, p97: 25.5),
        PercentileRow(month: 72, p3: 16.1, p15: 18.2, p50: 21.0, p85: 24.5, p97: 29.1),
        PercentileRow(month: 84, p3: 17.6, p15: 20.0, p50: 23.5, p85: 27.7, p97: 33.4),
        PercentileRow(month: 96, p3: 19.4, p15: 22.2, p50: 26.5, p85: 31.6, p97: 38.6),
        PercentileRow(month: 108, p3: 21.2, p15: 24.7, p50: 29.7, p85: 36.1, p97: 44.8),
        PercentileRow(month: 120, p3: 23.1, p15: 27.3, p50: 33.1, p85: 40.7, p97: 51.1),
        PercentileRow(month: 132, p3: 25.3, p15: 30.2, p50: 36.9, p85: 45.6, p97: 57.8),
        PercentileRow(month: 144, p3: 27.8, p15: 33.4, p50: 41.0, p85: 50.8, p97: 64.6),
        PercentileRow(month: 156, p3: 30.5, p15: 36.7, p50: 44.9, p85: 55.8, p97: 71.2),
        PercentileRow(month: 168, p3: 33.2, p15: 39.8, p50: 48.5, p85: 60.4, p97: 77.2),
        PercentileRow(month: 180, p3: 35.4, p15: 42.4, p50: 51.7, p85: 64.5, p97: 82.8),
        PercentileRow(month: 192, p3: 37.3, p15: 44.5, p50: 54.3, p85: 68.0, p97: 87.6),
        PercentileRow(month: 204, p3: 38.7, p15: 46.2, p50: 56.5, p85: 70.7, p97: 91.5),
        PercentileRow(month: 216, p3: 39.8, p15: 47.7, p50: 58.2, p85: 73.0, p97: 95.1),
        PercentileRow(month: 228, p3: 40.7, p15: 48.9, p50: 59.7, p85: 75.0, p97: 98.1),
        PercentileRow(month: 240, p3: 41.5, p15: 50.1, p50: 61.2, p85: 76.9, p97: 101.1),
    ]

    // MARK: - Lookup

    /// Linear interpolation between the two adjacent rows that bracket `ageMonths`.
    /// Ages outside the table clamp to its ends rather than extrapolating —
    /// `percentileRow` has already rejected anything past 240 months, and the
    /// tables start at birth.
    static func interpolate(_ table: [PercentileRow], ageMonths: Double) -> PercentileRow? {
        guard let first = table.first, let last = table.last else { return nil }
        if ageMonths <= first.month { return first }
        if ageMonths >= last.month { return last }

        for index in 0..<(table.count - 1) {
            let low = table[index]
            let high = table[index + 1]
            guard ageMonths >= low.month, ageMonths <= high.month else { continue }

            let span = high.month - low.month
            guard span > 0 else { return low }
            let t = (ageMonths - low.month) / span
            return PercentileRow(
                month: ageMonths,
                p3: low.p3 + t * (high.p3 - low.p3),
                p15: low.p15 + t * (high.p15 - low.p15),
                p50: low.p50 + t * (high.p50 - low.p50),
                p85: low.p85 + t * (high.p85 - low.p85),
                p97: low.p97 + t * (high.p97 - low.p97)
            )
        }
        return nil
    }

    /// The percentile row for an age, in **metric** units. `nil` outside 0–240
    /// months: past 20 years neither standard has a reference population, and a
    /// missing answer is better than one invented by extrapolation.
    ///
    /// `.other` averages the boys' and girls' tables, matching the web's handling
    /// of gender 2. It is a stand-in, not a third standard — neither WHO nor CDC
    /// publishes one.
    static func percentileRow(
        ageMonths: Double,
        gender: Gender,
        type: MeasurementType
    ) -> PercentileRow? {
        guard ageMonths >= 0, ageMonths <= maxAgeMonths else { return nil }

        let useWHO = ageMonths <= whoCutoffMonths
        let maleTable: [PercentileRow]
        let femaleTable: [PercentileRow]

        switch type {
        case .height:
            maleTable = useWHO ? whoHeightBoys : cdcHeightBoys
            femaleTable = useWHO ? whoHeightGirls : cdcHeightGirls
        case .weight:
            maleTable = useWHO ? whoWeightBoys : cdcWeightBoys
            femaleTable = useWHO ? whoWeightGirls : cdcWeightGirls
        }

        switch gender {
        case .male:
            return interpolate(maleTable, ageMonths: ageMonths)
        case .female:
            return interpolate(femaleTable, ageMonths: ageMonths)
        case .other:
            guard let male = interpolate(maleTable, ageMonths: ageMonths),
                  let female = interpolate(femaleTable, ageMonths: ageMonths) else {
                return interpolate(maleTable, ageMonths: ageMonths)
                    ?? interpolate(femaleTable, ageMonths: ageMonths)
            }
            return PercentileRow(
                month: ageMonths,
                p3: (male.p3 + female.p3) / 2,
                p15: (male.p15 + female.p15) / 2,
                p50: (male.p50 + female.p50) / 2,
                p85: (male.p85 + female.p85) / 2,
                p97: (male.p97 + female.p97) / 2
            )
        }
    }

    // MARK: - Ranking

    /// Where a metric value falls, as an approximate percentile rank. `.below`
    /// rather than a number under the 3rd: the tables carry no band down there to
    /// interpolate inside, so any figure would be invented.
    enum Rank: Equatable {
        case below
        case value(Double)
    }

    static func approximateRank(metricValue: Double, in row: PercentileRow) -> Rank {
        if metricValue < row.p3 { return .below }

        if metricValue > row.p97 {
            let span = row.p97 - row.p85
            guard span > 1e-9 else { return .value(97) }
            // Extrapolate along the 85th–97th slope so a value above the top band
            // still gets a figure instead of collapsing to a flat ">97th".
            let extra = ((metricValue - row.p97) / span) * (97 - 85)
            return .value(min(99.9, 97 + extra))
        }

        let segments: [(low: Double, high: Double, pLow: Double, pHigh: Double)] = [
            (row.p3, row.p15, 3, 15),
            (row.p15, row.p50, 15, 50),
            (row.p50, row.p85, 50, 85),
            (row.p85, row.p97, 85, 97),
        ]

        for segment in segments where metricValue >= segment.low && metricValue <= segment.high {
            let span = segment.high - segment.low
            guard span > 1e-9 else { return .value(segment.pLow) }
            let t = (metricValue - segment.low) / span
            return .value(segment.pLow + t * (segment.pHigh - segment.pLow))
        }
        return .value(50)
    }

    /// A human-readable percentile, e.g. "~75th %ile", "<3rd %ile", "~99.2th %ile".
    /// `nil` when the age is out of range, which is also how a person with no
    /// birthday is handled — the caller has no age to pass.
    static func percentileLabel(
        value: Double,
        unit: MeasurementUnit,
        ageMonths: Double,
        gender: Gender,
        type: MeasurementType
    ) -> String? {
        guard ageMonths >= 0, ageMonths <= maxAgeMonths else { return nil }
        guard let row = percentileRow(ageMonths: ageMonths, gender: gender, type: type) else {
            return nil
        }

        switch approximateRank(metricValue: MeasurementConversion.toMetric(value, from: unit), in: row) {
        case .below:
            return "<3rd %ile"
        case .value(let rank):
            if rank > 97 {
                return String(format: "~%.1fth %%ile", rank)
            }
            let rounded = Int(rank.rounded())
            return "~\(rounded)\(ordinalSuffix(rounded)) %ile"
        }
    }

    private static func ordinalSuffix(_ n: Int) -> String {
        switch n {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    // MARK: - Age

    /// Age in months, fractional. This is the web's arithmetic
    /// (`yearDiff * 12 + monthDiff + dayDiff / 30.4375`) rather than a
    /// `Calendar` interval, because a percentile the two clients disagree on is
    /// worse than one that is a fraction of a month off the calendar truth: the
    /// day component is deliberately *not* normalised, so it can be negative and
    /// pull the total back below the whole-month boundary.
    static func ageInMonths(
        birthday: Date,
        on date: Date,
        calendar: Calendar = .current
    ) -> Double {
        let birth = calendar.dateComponents([.year, .month, .day], from: birthday)
        let measured = calendar.dateComponents([.year, .month, .day], from: date)
        guard let birthYear = birth.year, let birthMonth = birth.month, let birthDay = birth.day,
              let year = measured.year, let month = measured.month, let day = measured.day else {
            return 0
        }
        let wholeMonths = (year - birthYear) * 12 + (month - birthMonth)
        return Double(wholeMonths) + Double(day - birthDay) / 30.4375
    }

    /// "8 mo", "3 yr", "3 yr 4 mo" — the web's `formatAgeAtMeasurement`. Under
    /// two years it stays in months, because "1 yr 1 mo" tells a parent less than
    /// "13 mo" does.
    static func formatAge(months: Double) -> String {
        if months < 0 { return "—" }
        if months < 24 {
            let value = Int(months.rounded())
            return value == 1 ? "1 mo" : "\(value) mo"
        }
        let total = Int(months.rounded())
        let years = total / 12
        let remainder = total % 12
        if remainder == 0 {
            return years == 1 ? "1 yr" : "\(years) yr"
        }
        return "\(years) yr \(remainder) mo"
    }
}
