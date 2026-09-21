import Model

/// 지표 한 묶음을 읽는 단위. 메모리·CPU·GPU·디스크·열·컨텍스트가 각각 하나씩 구현한다 (F-02~F-08).
///
/// 읽기 실패는 `throw`가 아니라 `nil`이다. 수집은 멈추지 않고 그 샘플의 해당 항목만 결측으로
/// 남긴다 (요구사항 8장 견고성). 비공개 API(IOReport, SMC)를 쓰는 구현은 OS 업데이트로 언제든
/// `nil`만 돌려줄 수 있다는 전제로 짠다.
///
/// 수집기 전체 예산은 CPU 평균 1% 미만, 상주 메모리 50MB 미만이다 (F-10).
///
/// `Reading`을 기본 연관 타입으로 둔다. 수집 루프가 `any Sampler<MemoryReading>`로 받아야
/// 테스트가 실기기 대신 더블을 넣을 수 있다.
public protocol Sampler<Reading>: Sendable {
    associatedtype Reading: Sendable

    func read() -> Reading?
}
