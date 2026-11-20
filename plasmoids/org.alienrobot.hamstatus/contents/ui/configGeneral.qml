import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_endpoint: endpoint.text
    property alias cfg_pollSeconds: pollSeconds.value
    property alias cfg_horizontalScalePercent: horizontalScale.value
    property alias cfg_verticalScalePercent: verticalScale.value

    QQC2.TextField {
        id: endpoint
        Kirigami.FormData.label: i18n("Health endpoint:")
        placeholderText: "https://home.alienrobot.org/api/services"
        selectByMouse: true
    }

    QQC2.SpinBox {
        id: pollSeconds
        Kirigami.FormData.label: i18n("Poll interval:")
        from: 5
        to: 120
        stepSize: 5
        editable: true
        textFromValue: function(value) { return value + " s"; }
        valueFromText: function(text) {
            const parsed = parseInt(text, 10);
            return isNaN(parsed) ? 10 : parsed;
        }
    }

    QQC2.SpinBox {
        id: horizontalScale
        Kirigami.FormData.label: i18n("Horizontal scale:")
        from: 50
        to: 200
        stepSize: 5
        editable: true
        textFromValue: function(value) { return value + "%"; }
        valueFromText: function(text) {
            const parsed = parseInt(text, 10);
            return isNaN(parsed) ? 100 : parsed;
        }
    }

    QQC2.SpinBox {
        id: verticalScale
        Kirigami.FormData.label: i18n("Vertical scale:")
        from: 50
        to: 200
        stepSize: 5
        editable: true
        textFromValue: function(value) { return value + "%"; }
        valueFromText: function(text) {
            const parsed = parseInt(text, 10);
            return isNaN(parsed) ? 100 : parsed;
        }
    }

    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: i18n("One tiny cached JSON request per poll. The widget performs no service probes itself.")
        wrapMode: Text.Wrap
    }
}
