import Foundation
import HealthKit

final class HealthKitService {
    private let healthStore = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { return }

        var readTypes: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        ]

        // VO2 max — available on watchOS / newer iPhones
        if let vo2 = HKObjectType.quantityType(forIdentifier: .vo2Max) {
            readTypes.insert(vo2)
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    func fetchHealthContext() async -> HealthContext {
        async let sleep        = fetchLastNightSleep()
        async let hrv          = fetchLatestHRV()
        async let hrvWeek      = fetchWeekAverageHRV()
        async let rhr          = fetchLatestRestingHeartRate()
        async let respiratory  = fetchLatestRespiratoryRate()
        async let vo2          = fetchLatestVO2Max()
        async let calories     = fetchYesterdayActiveCalories()

        let (sleepResult, hrvVal, hrvWeekVal, rhrVal, respVal, vo2Val, calVal) =
            await (sleep, hrv, hrvWeek, rhr, respiratory, vo2, calories)

        return HealthContext(
            sleepDuration:       sleepResult?.total,
            sleepDeepHours:      sleepResult?.deep,
            sleepREMHours:       sleepResult?.rem,
            hrvValue:            hrvVal,
            hrvWeekAverage:      hrvWeekVal,
            restingHeartRate:    rhrVal,
            respiratoryRate:     respVal,
            vo2Max:              vo2Val,
            activeCaloriesBurned: calVal
        )
    }

    // MARK: - Sleep

    private struct SleepBreakdown {
        let total: Double
        let deep: Double?
        let rem: Double?
    }

    private func fetchLastNightSleep() async -> SleepBreakdown? {
        guard isAvailable else { return nil }

        let sleepType = HKCategoryType(.sleepAnalysis)
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let windowStart  = Calendar.current.date(byAdding: .hour, value: -12, to: startOfToday)!

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: now, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )

        do {
            let samples = try await descriptor.result(for: healthStore)
            let deepSeconds = samples
                .filter { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            let remSeconds = samples
                .filter { $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            let totalSeconds = samples
                .filter {
                    $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

            guard totalSeconds > 0 else { return nil }
            return SleepBreakdown(
                total: totalSeconds / 3600,
                deep:  deepSeconds > 0 ? deepSeconds / 3600 : nil,
                rem:   remSeconds > 0  ? remSeconds / 3600  : nil
            )
        } catch { return nil }
    }

    // MARK: - HRV

    private func fetchLatestHRV() async -> Double? {
        await fetchLatestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), lookbackDays: 1)
    }

    private func fetchWeekAverageHRV() async -> Double? {
        guard isAvailable else { return nil }

        let type = HKQuantityType(.heartRateVariabilitySDNN)
        let unit = HKUnit.secondUnit(with: .milli)
        let now  = Date()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: weekAgo, end: now, options: .strictStartDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        do {
            let samples = try await descriptor.result(for: healthStore)
            guard !samples.isEmpty else { return nil }
            let values = samples.map { $0.quantity.doubleValue(for: unit) }
            return values.reduce(0, +) / Double(values.count)
        } catch { return nil }
    }

    // MARK: - Other quantities

    private func fetchLatestRestingHeartRate() async -> Double? {
        await fetchLatestQuantity(.restingHeartRate, unit: .count().unitDivided(by: .minute()), lookbackDays: 1)
    }

    private func fetchLatestRespiratoryRate() async -> Double? {
        await fetchLatestQuantity(.respiratoryRate, unit: .count().unitDivided(by: .minute()), lookbackDays: 1)
    }

    private func fetchLatestVO2Max() async -> Double? {
        let unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        return await fetchLatestQuantity(.vo2Max, unit: unit, lookbackDays: 30)
    }

    private func fetchYesterdayActiveCalories() async -> Double? {
        guard isAvailable else { return nil }

        let type = HKQuantityType(.activeEnergyBurned)
        let cal  = Calendar.current
        let now  = Date()
        let endOfYesterday   = cal.startOfDay(for: now)
        let startOfYesterday = cal.date(byAdding: .day, value: -1, to: endOfYesterday)!
        let predicate = HKQuery.predicateForSamples(withStart: startOfYesterday, end: endOfYesterday, options: .strictStartDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        do {
            let samples = try await descriptor.result(for: healthStore)
            let total = samples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .kilocalorie()) }
            return total > 0 ? total : nil
        } catch { return nil }
    }

    // MARK: - Generic helper

    private func fetchLatestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit, lookbackDays: Int) async -> Double? {
        guard isAvailable else { return nil }

        guard let type = HKObjectType.quantityType(forIdentifier: id) as? HKQuantityType else { return nil }
        let now  = Date()
        let from = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: from, end: now, options: .strictStartDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        do {
            let samples = try await descriptor.result(for: healthStore)
            return samples.first?.quantity.doubleValue(for: unit)
        } catch { return nil }
    }
}
