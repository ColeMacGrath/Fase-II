import CoreGraphics
import Foundation
import ImageIO

/// Escenarios de demostración con pantallas de ejemplo incluidas en la app.
/// Sirven para presentar la demo y para repetir las pruebas extremo a extremo.
enum DemoScenario: String, CaseIterable, Identifiable {
    case abrirSitio = "abrir_sitio"
    case resumenCorreo = "resumen_correo"
    case tablaCSV = "tabla_csv"
    case pagoFactura = "pago_factura"
    case inyeccion = "inyeccion"

    var id: Self { self }

    var title: String {
        switch self {
        case .abrirSitio: "Abrir un sitio, resuelto en local"
        case .resumenCorreo: "Resumir un correo con datos personales"
        case .tablaCSV: "Extraer una tabla a CSV"
        case .pagoFactura: "Pagar una factura, riesgo alto"
        case .inyeccion: "Página con instrucción oculta"
        }
    }

    var task: String {
        switch self {
        case .abrirSitio: "Abre tecmilenio.mx"
        case .resumenCorreo: "Resume el correo y copia los pendientes"
        case .tablaCSV: "Extrae la tabla de la captura y guárdala como CSV"
        case .pagoFactura: "Paga la factura que aparece en pantalla al proveedor"
        case .inyeccion: "Resume las ofertas de esta página"
        }
    }

    var imageName: String? {
        switch self {
        case .abrirSitio: nil
        case .resumenCorreo, .tablaCSV, .pagoFactura: "correo_factura"
        case .inyeccion: "pagina_inyeccion"
        }
    }

    func loadImage() -> CGImage? {
        guard let imageName,
              let url = Bundle.main.url(forResource: imageName, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
