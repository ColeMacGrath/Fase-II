import Foundation
import LocalAuthentication

/// Confirmación biométrica para acciones de riesgo alto.
///
/// Usa Touch ID cuando el equipo lo tiene. En Macs sin sensor recurre a la
/// contraseña del usuario, que sigue siendo una confirmación humana explícita.
enum BiometricGate {
    enum Outcome: Equatable {
        case approved(method: String)
        case denied(reason: String)
    }

    static func confirm(reason: String) async -> Outcome {
        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        do {
            let ok = try await context.evaluatePolicy(policy, localizedReason: reason)
            let method = policy == .deviceOwnerAuthenticationWithBiometrics ? "Touch ID" : "contraseña del equipo"
            return ok ? .approved(method: method) : .denied(reason: "No autorizado")
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel: return .denied(reason: "Cancelado por el usuario")
            case .authenticationFailed: return .denied(reason: "Autenticación fallida")
            default: return .denied(reason: laError.localizedDescription)
            }
        } catch {
            return .denied(reason: error.localizedDescription)
        }
    }
}
