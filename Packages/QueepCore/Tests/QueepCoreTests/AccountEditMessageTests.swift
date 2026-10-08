import XCTest
@testable import QueepCore

final class AccountEditMessageTests: XCTestCase {
    func testEachFieldReplacesTheSignInFallback() {
        let contexts: [AccountEditContext] = [.name, .email, .password, .link]
        for context in contexts {
            let text = AccountEditMessage.resolve(AccountEditMessage.signInFallback, context: context)
            XCTAssertEqual(text, AccountEditMessage.genericFailure(context))
            XCTAssertFalse(text.contains("Não foi possível entrar"))
            XCTAssertFalse(text.isEmpty)
        }
        let messages = Set(contexts.map { AccountEditMessage.genericFailure($0) })
        XCTAssertEqual(messages.count, contexts.count)
    }

    func testAppleAndGoogleSignInSentencesBecomeFieldCopy() {
        let apple = "Não foi possível entrar com a Apple."
        let google = "Não foi possível entrar com o Google."
        XCTAssertEqual(AccountEditMessage.resolve(apple, context: .link),
                       AccountEditMessage.genericFailure(.link))
        XCTAssertEqual(AccountEditMessage.resolve(google, context: .link),
                       AccountEditMessage.genericFailure(.link))
        XCTAssertEqual(AccountEditMessage.resolve(apple, context: .name),
                       AccountEditMessage.genericFailure(.name))
    }

    func testCancellationStaysSilent() {
        XCTAssertEqual(AccountEditMessage.resolve("", context: .email), "")
        XCTAssertEqual(AccountEditMessage.resolve("   ", context: .password), "")
    }

    func testSpecificFailuresStayAsWritten() {
        let samples = [
            "Digite um e-mail válido.",
            "A senha precisa ter pelo menos 6 caracteres.",
            "Sem conexão. Tente de novo em alguns instantes.",
            "Já existe uma conta com este e-mail. Entre com o método que você usou antes.",
            "Este login já está vinculado a esta conta.",
            "Mantenha pelo menos um método para entrar na conta.",
            "Sua sessão expirou. Entre novamente.",
            "Cadastre um e-mail antes de criar uma senha."
        ]
        for sample in samples {
            XCTAssertEqual(AccountEditMessage.resolve(sample, context: .email), sample)
            XCTAssertEqual(AccountEditMessage.resolve(sample, context: .password), sample)
            XCTAssertEqual(AccountEditMessage.resolve(sample, context: .link), sample)
            XCTAssertEqual(AccountEditMessage.resolve(sample, context: .name), sample)
        }
    }
}
