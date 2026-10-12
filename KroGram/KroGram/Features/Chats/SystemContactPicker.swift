import Contacts
import ContactsUI
import SwiftUI

struct ContactShareSelection {
    let firstName: String
    let lastName: String
    let phoneNumber: String
}

struct SystemContactPicker: UIViewControllerRepresentable {
    let onSelect: (ContactShareSelection?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let onSelect: (ContactShareSelection?) -> Void

        init(onSelect: @escaping (ContactShareSelection?) -> Void) {
            self.onSelect = onSelect
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            guard let number = contact.phoneNumbers.first?.value.stringValue,
                  !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                onSelect(nil)
                return
            }
            onSelect(ContactShareSelection(
                firstName: contact.givenName,
                lastName: contact.familyName,
                phoneNumber: number
            ))
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onSelect(nil)
        }
    }
}
