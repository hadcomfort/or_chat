import SwiftUI

struct ContentView: View {
    var body: some View {
        ChatView()
            .frame(minWidth: 400, idealWidth: 500, maxWidth: .infinity,
                   minHeight: 300, idealHeight: 600, maxHeight: .infinity)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
