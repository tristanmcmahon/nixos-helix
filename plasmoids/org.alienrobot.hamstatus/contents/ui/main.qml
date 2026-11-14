import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    readonly property real horizontalScale: Math.max(0.5, Math.min(2.0,
        plasmoid.configuration.horizontalScalePercent / 100.0))
    readonly property real verticalScale: Math.max(0.5, Math.min(2.0,
        plasmoid.configuration.verticalScalePercent / 100.0))
    readonly property real pipSize: Math.max(14, Math.round(18 * Math.min(horizontalScale, verticalScale)))
    readonly property real horizontalGap: Math.max(3, Math.round(6 * horizontalScale))
    readonly property real verticalGap: Math.max(3, Math.round(6 * verticalScale))
    readonly property color phosphorGreen: "#78ff6b"
    readonly property color phosphorAmber: "#e6b85c"
    readonly property color phosphorRed: "#ff6654"
    readonly property color phosphorDim: "#63745d"
    readonly property color bezelDark: "#151a14"
    readonly property bool verticalPanel: plasmoid.formFactor === PlasmaCore.Types.Vertical

    property var serviceState: ({})
    property bool authorityReachable: false
    property bool requestInFlight: false
    property var currentRequest: null
    property int selectedGroup: 0
    property double lastUpdatedEpoch: 0

    readonly property var groups: [
        {
            key: "arr",
            label: "ARR",
            services: [
                { key: "sonarr", label: "Sonarr", detail: "television", url: "https://sonarr.home.alienrobot.org" },
                { key: "radarr", label: "Radarr", detail: "movies", url: "https://radarr.home.alienrobot.org" },
                { key: "whisparr", label: "Whisparr", detail: "adult media", url: "https://xxx.home.alienrobot.org" },
                { key: "prowlarr", label: "Prowlarr", detail: "indexers", url: "https://prowlarr.home.alienrobot.org" }
            ]
        },
        {
            key: "media",
            label: "MEDIA",
            services: [
                { key: "plex", label: "Plex", detail: "library", url: "http://plex.home.alienrobot.org:32400/web" },
                { key: "seerr", label: "Seerr", detail: "requests", url: "https://seerr.home.alienrobot.org" },
                { key: "mylar", label: "Mylar", detail: "comics", url: "https://mylar.home.alienrobot.org" },
                { key: "books", label: "LazyLibrarian", detail: "books", url: "https://books.home.alienrobot.org" }
            ]
        },
        {
            key: "downloads",
            label: "GET",
            services: [
                { key: "sab", label: "SABnzbd", detail: "usenet", url: "https://sab.home.alienrobot.org" },
                { key: "deluge", label: "Deluge", detail: "torrents", url: "https://deluge.home.alienrobot.org" }
            ]
        },
        {
            key: "system",
            label: "SYS",
            services: [
                { key: "netdata", label: "Netdata", detail: "telemetry", url: "https://netdata.home.alienrobot.org" },
                { key: "pihole", label: "Pi-hole", detail: "DNS", url: "https://pihole.home.alienrobot.org/admin/" },
                { key: "dsm", label: "DSM", detail: "NAS", url: "https://dsm.home.alienrobot.org" }
            ]
        }
    ]

    activationTogglesExpanded: false
    toolTipMainText: i18n("alienrobot service health")
    toolTipSubText: root.overallSummary()

    function statusColor(status) {
        if (status === "up")
            return phosphorGreen;
        if (status === "degraded")
            return phosphorAmber;
        if (status === "down")
            return phosphorRed;
        return phosphorDim;
    }

    function serviceStatus(key) {
        if (!authorityReachable)
            return "unknown";
        const value = serviceState[key];
        if (value === true)
            return "up";
        if (value === false)
            return "down";
        return "unknown";
    }

    function groupStatus(groupIndex) {
        if (!authorityReachable)
            return "unknown";

        const services = groups[groupIndex].services;
        let known = 0;
        let up = 0;
        for (let i = 0; i < services.length; ++i) {
            const value = serviceState[services[i].key];
            if (value === true || value === false) {
                known += 1;
                if (value === true)
                    up += 1;
            }
        }

        if (known === 0)
            return "unknown";
        if (known === services.length && up === services.length)
            return "up";
        if (known === services.length && up === 0)
            return "down";
        return "degraded";
    }

    function statusLabel(status) {
        if (status === "up")
            return i18n("healthy");
        if (status === "degraded")
            return i18n("degraded");
        if (status === "down")
            return i18n("down");
        return i18n("unknown");
    }

    function overallSummary() {
        if (!authorityReachable)
            return i18n("health authority unavailable");

        let degraded = 0;
        let down = 0;
        for (let i = 0; i < groups.length; ++i) {
            const state = groupStatus(i);
            if (state === "degraded")
                degraded += 1;
            else if (state === "down")
                down += 1;
        }
        if (down > 0)
            return i18np("%1 group down", "%1 groups down", down);
        if (degraded > 0)
            return i18np("%1 group degraded", "%1 groups degraded", degraded);
        return i18n("all groups healthy");
    }

    function finishRequest(success, payload) {
        requestWatchdog.stop();
        requestInFlight = false;
        currentRequest = null;

        if (!success) {
            authorityReachable = false;
            return;
        }

        serviceState = payload;
        authorityReachable = true;
        lastUpdatedEpoch = Date.now() / 1000;
    }

    function refresh() {
        if (requestInFlight)
            return;

        const endpoint = String(plasmoid.configuration.endpoint || "").trim();
        if (!endpoint) {
            authorityReachable = false;
            return;
        }

        const request = new XMLHttpRequest();
        currentRequest = request;
        requestInFlight = true;
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE)
                return;

            if (request.status < 200 || request.status >= 300) {
                root.finishRequest(false, null);
                return;
            }

            try {
                const payload = JSON.parse(request.responseText);
                if (!payload || typeof payload !== "object" || Array.isArray(payload))
                    throw new Error("invalid service payload");
                root.finishRequest(true, payload);
            } catch (_) {
                root.finishRequest(false, null);
            }
        };

        try {
            request.open("GET", endpoint);
            request.setRequestHeader("Accept", "application/json");
            requestWatchdog.restart();
            request.send();
        } catch (_) {
            root.finishRequest(false, null);
        }
    }

    Timer {
        id: pollTimer
        interval: Math.max(5, plasmoid.configuration.pollSeconds) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: requestWatchdog
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.currentRequest)
                root.currentRequest.abort();
            root.currentRequest = null;
            root.requestInFlight = false;
            root.authorityReachable = false;
        }
    }

    compactRepresentation: Component {
        Item {
            implicitWidth: root.verticalPanel
                ? Math.ceil(root.pipSize + 8 * root.horizontalScale)
                : Math.ceil(root.groups.length * root.pipSize
                    + (root.groups.length - 1) * root.horizontalGap
                    + 8 * root.horizontalScale)
            implicitHeight: root.verticalPanel
                ? Math.ceil(root.groups.length * root.pipSize
                    + (root.groups.length - 1) * root.verticalGap
                    + 8 * root.verticalScale)
                : Math.ceil(root.pipSize + 8 * root.verticalScale)

            Flow {
                anchors.centerIn: parent
                width: root.verticalPanel ? root.pipSize
                    : root.groups.length * root.pipSize + (root.groups.length - 1) * root.horizontalGap
                height: root.verticalPanel
                    ? root.groups.length * root.pipSize + (root.groups.length - 1) * root.verticalGap
                    : root.pipSize
                flow: root.verticalPanel ? Flow.TopToBottom : Flow.LeftToRight
                spacing: root.verticalPanel ? root.verticalGap : root.horizontalGap

                Repeater {
                    model: root.groups.length

                    delegate: Item {
                        required property int index
                        readonly property var group: root.groups[index]
                        readonly property string state: root.groupStatus(index)

                        width: root.pipSize
                        height: root.pipSize

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: root.bezelDark
                            border.width: Math.max(1, Math.round(width * 0.10))
                            border.color: Qt.darker(root.statusColor(parent.state), 1.65)

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width * 0.72
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.width: Math.max(1, Math.round(parent.width * 0.08))
                                border.color: root.statusColor(parent.parent.state)
                                opacity: parent.parent.state === "unknown" ? 0.45 : 0.95
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width * 0.34
                                height: width
                                radius: width / 2
                                color: root.statusColor(parent.parent.state)
                                opacity: parent.parent.state === "unknown" ? 0.45 : 1.0
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                width: Math.max(1, parent.width * 0.10)
                                height: Math.max(2, parent.height * 0.18)
                                color: root.statusColor(parent.parent.state)
                                opacity: 0.65
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                width: Math.max(1, parent.width * 0.10)
                                height: Math.max(2, parent.height * 0.18)
                                color: root.statusColor(parent.parent.state)
                                opacity: 0.65
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                width: Math.max(2, parent.width * 0.18)
                                height: Math.max(1, parent.height * 0.10)
                                color: root.statusColor(parent.parent.state)
                                opacity: 0.65
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                width: Math.max(2, parent.width * 0.18)
                                height: Math.max(1, parent.height * 0.10)
                                color: root.statusColor(parent.parent.state)
                                opacity: 0.65
                            }
                        }

                        MouseArea {
                            id: pipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedGroup = parent.index;
                                plasmoid.expanded = true;
                            }

                            QQC2.ToolTip.visible: containsMouse
                            QQC2.ToolTip.delay: 350
                            QQC2.ToolTip.text: parent.group.label + " · " + root.statusLabel(parent.state)
                        }
                    }
                }
            }
        }
    }

    fullRepresentation: Component {
        Item {
            implicitWidth: Math.round(320 * root.horizontalScale)
            implicitHeight: Math.round(250 * root.verticalScale)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Math.max(8, Math.round(10 * root.horizontalScale))
                spacing: Math.max(6, Math.round(8 * root.verticalScale))

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Math.max(4, Math.round(6 * root.horizontalScale))

                    Repeater {
                        model: root.groups.length

                        delegate: Rectangle {
                            required property int index
                            readonly property var group: root.groups[index]
                            readonly property string state: root.groupStatus(index)

                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.round(30 * root.verticalScale)
                            radius: 5
                            color: index === root.selectedGroup
                                ? Kirigami.Theme.highlightColor
                                : "transparent"
                            border.width: index === root.selectedGroup ? 0 : 1
                            border.color: Kirigami.Theme.disabledTextColor

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: Math.max(3, Math.round(4 * root.horizontalScale))

                                Item {
                                    width: Math.max(12, Math.round(15 * Math.min(root.horizontalScale, root.verticalScale)))
                                    height: width

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: root.bezelDark
                                        border.width: 1
                                        border.color: Qt.darker(root.statusColor(parent.parent.parent.state), 1.55)
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width * 0.62
                                        height: width
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: 1
                                        border.color: root.statusColor(parent.parent.parent.state)
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width * 0.26
                                        height: width
                                        radius: width / 2
                                        color: root.statusColor(parent.parent.parent.state)
                                    }
                                }

                                Text {
                                    text: parent.parent.group.label
                                    color: index === root.selectedGroup
                                        ? Kirigami.Theme.highlightedTextColor
                                        : Kirigami.Theme.textColor
                                    font.bold: index === root.selectedGroup
                                    font.pixelSize: Math.max(9, Math.round(11 * root.verticalScale))
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedGroup = parent.index
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Kirigami.Theme.disabledTextColor
                    opacity: 0.35
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Math.max(3, Math.round(4 * root.verticalScale))

                    Repeater {
                        model: root.groups[root.selectedGroup].services

                        delegate: Rectangle {
                            id: serviceRow
                            required property var modelData
                            readonly property string state: root.serviceStatus(modelData.key)

                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.round(38 * root.verticalScale)
                            radius: 5
                            color: rowMouse.containsMouse ? Kirigami.Theme.hoverColor : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Math.round(8 * root.horizontalScale)
                                anchors.rightMargin: Math.round(8 * root.horizontalScale)
                                spacing: Math.max(7, Math.round(9 * root.horizontalScale))

                                Item {
                                    width: Math.max(12, Math.round(15 * Math.min(root.horizontalScale, root.verticalScale)))
                                    height: width

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: root.bezelDark
                                        border.width: 1
                                        border.color: Qt.darker(root.statusColor(serviceRow.state), 1.55)
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width * 0.60
                                        height: width
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: 1
                                        border.color: root.statusColor(serviceRow.state)
                                        opacity: serviceRow.state === "unknown" ? 0.45 : 0.95
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width * 0.24
                                        height: width
                                        radius: width / 2
                                        color: root.statusColor(serviceRow.state)
                                        opacity: serviceRow.state === "unknown" ? 0.45 : 1.0
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        Layout.fillWidth: true
                                        text: serviceRow.modelData.label
                                        color: Kirigami.Theme.textColor
                                        elide: Text.ElideRight
                                        font.pixelSize: Math.max(10, Math.round(12 * root.verticalScale))
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: serviceRow.modelData.detail + " · " + root.statusLabel(serviceRow.state)
                                        color: Kirigami.Theme.disabledTextColor
                                        elide: Text.ElideRight
                                        font.pixelSize: Math.max(8, Math.round(10 * root.verticalScale))
                                    }
                                }

                                Text {
                                    text: "↗"
                                    color: Kirigami.Theme.disabledTextColor
                                    font.pixelSize: Math.max(10, Math.round(13 * root.verticalScale))
                                }
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally(serviceRow.modelData.url)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        text: root.authorityReachable
                            ? i18n("hamFence · cached reachability")
                            : i18n("hamFence health feed unavailable")
                        color: root.authorityReachable
                            ? Kirigami.Theme.disabledTextColor
                            : Kirigami.Theme.negativeTextColor
                        font.pixelSize: Math.max(8, Math.round(9 * root.verticalScale))
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "↻"
                        color: Kirigami.Theme.textColor
                        font.pixelSize: Math.max(11, Math.round(14 * root.verticalScale))

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refresh()

                            QQC2.ToolTip.visible: containsMouse
                            QQC2.ToolTip.text: i18n("Refresh now")
                        }
                    }
                }
            }
        }
    }
}
